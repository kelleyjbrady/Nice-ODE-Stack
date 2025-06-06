FROM nvidia/cuda:12.4.1-base-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    # --- Locale Settings ---
    # Set the language and locale to en_US.UTF-8 system-wide
    # This prevents locale warnings in R, Python, and other tools.
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    # Set user/group IDs
    USER_UID=1000 \
    USER_GID=1000 \
    # Disable virtualenv creation in project directory, store centrally
    POETRY_VIRTUALENVS_IN_PROJECT=false \
    POETRY_VIRTUALENVS_PATH=/opt/poetry-venvs \
    # Add poetry bin to PATH for root during build and later for the user
    # Note: Installer puts it in .local/bin for the executing user (root here)
    PATH="/root/.local/bin:$PATH"

# --- System Setup ---
# Install system dependencies: Python, pip, git, common utilities, and build tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # Prerequisites for adding repositories
        software-properties-common \
        dirmngr \
        # Locales package
        locales \
        # Compilers and build tools
        g++ \
        build-essential \
        cmake \
        # Common utilities
        graphviz \
        git \
        wget \
        curl \
        vim \
        nano \
    # Add the CRAN GPG key and repository for Ubuntu 22.04 (Jammy)
    && wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc && \
    add-apt-repository 'deb https://cloud.r-project.org/bin/linux/ubuntu jammy-cran40/' && \
    # Update apt lists again and install R and its dependencies
    apt-get update && \
    apt-get install -y --no-install-recommends \
        r-base \
        r-base-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
         libfribidi-dev \
        libcairo2-dev \
        libxt-dev \
        # Added for symengine and other scientific packages
        libgmp-dev \
        libmpfr-dev \
    # Clean up apt caches to reduce image size
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Generate Locale ---
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
locale-gen

# --- Python Setup ---
# Install prerequisites for adding PPAs if necessary (curl/wget already there)
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    # Add the deadsnakes PPA
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update

# Example: Install Python 3.13 (adjust version as needed/available)
RUN apt-get install -y --no-install-recommends \   
        python3.13 \
        python3.13-dev \
        python3.13-venv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Update alternatives to make python3 point to python3.13
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 2 && \
    update-alternatives --set python3 /usr/bin/python3.13

# Ensure pip is correctly linked, install 'tools' into the system python
RUN python3 -m ensurepip --upgrade && \
 pip3 install --no-cache-dir --upgrade pip && \
 pip3 install --no-cache-dir poetry
 # Optional: Add completions globally
RUN mkdir -p /etc/bash_completion.d && \
poetry completions bash > /etc/bash_completion.d/poetry.bash


# --- Julia Setup ---
# Download and install Julia from official binaries
RUN cd /tmp && \
    wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.11/julia-1.11.4-linux-x86_64.tar.gz && \
    # Optional: Add SHA256 verification here if needed
    # echo "<EXPECTED_SHA256_HASH> *julia-${JULIA_VERSION}-linux-x86_64.tar.gz" | sha256sum -c - && \
    tar -xzf julia-1.11.4-linux-x86_64.tar.gz -C /opt/ && \
    ln -s /opt/julia-1.11.4/bin/julia /usr/local/bin/julia && \
    rm julia-1.11.4-linux-x86_64.tar.gz && \
    # Verify installation
    julia --version


#R package installation
COPY r_requirements.txt install_R_pkgs.R /tmp/
RUN cd /tmp && Rscript install_R_pkgs.R && rm /tmp/r_requirements.txt /tmp/install_R_pkgs.R


# --- Application Setup (as root for installation) ---
# Set a work directory for the application build steps
ARG DEV_TOOLS_PROJ_PATH=/workspaces/cuda-py-dev-tools
WORKDIR $DEV_TOOLS_PROJ_PATH

# Copy only dependency definition files first to leverage Docker cache
COPY pyproject.toml poetry.lock* ./

# ---- User setup ----
ARG USERNAME=vscode
# Create the user group and user; -m creates the home directory
# Do this *before* creating user-owned directories
RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME


# Create necessary directories needed by the user and set ownership *before* switching user
RUN mkdir -p ${POETRY_VIRTUALENVS_PATH} /home/${USERNAME}/R/library && \
    chown ${USERNAME}:${USER_GID} ${POETRY_VIRTUALENVS_PATH} /home/${USERNAME}/R /home/${USERNAME}/R/library

# --- Copy user .Rprofile to ensure user library path is prioritized ---
# Copy the pre-made .Rprofile into the user's home directory
COPY .Rprofile /home/${USERNAME}/.Rprofile
# Ensure the .Rprofile is owned by the user
RUN chown ${USERNAME}:${USER_GID} /home/${USERNAME}/.Rprofile


# Install dev tools dependencies using Poetry
# --no-interaction: Do not ask interactive questions
# --no-ansi: Produce plain output
# --no-root: Skip installing the project package itself (if it's an app, not a library)
# This command creates the virtualenv based on POETRY_VIRTUALENVS_PATH
RUN poetry install --no-interaction --no-ansi --no-root --no-cache

# --- Make tools from the dev tools venv easily accessible ---
# Get the full path to the virtual environment created by the 'poetry install' above
RUN DEV_TOOLS_VENV_PATH=$(poetry env info --path) && \
    echo "Dev tools venv path: ${DEV_TOOLS_VENV_PATH}" && \
    # Add this venv's bin directory to the PATH for all users/shells
    # This makes tools like ruff, radian, jupyter callable directly
    echo "export PATH=\"${DEV_TOOLS_VENV_PATH}/bin:\$PATH\"" >> /etc/bash.bashrc && \
    echo "export PATH=\"${DEV_TOOLS_VENV_PATH}/bin:\$PATH\"" > /etc/profile.d/dev_tools_poetry_env.sh && \
    chmod +x /etc/profile.d/dev_tools_poetry_env.sh

RUN rm -rf /build_env_tools # Clean up build context directory

# Copy the rest of the application source code
COPY . .

#Grant ownership of the app directory AND the *contents* of the venvs to the user
# The parent /opt/poetry-venvs is already owned by the user from the earlier step
RUN chown -R $USERNAME:$USER_GID ${DEV_TOOLS_PROJ_PATH} ${POETRY_VIRTUALENVS_PATH}

# Switch context to the non-root user
USER $USERNAME

# Set home environment variable and update PATH for user's local bin and poetry
# Note: The poetry executable itself should now be accessible via the inherited PATH
# or we can explicitly add the expected user location if needed.
# The venv path is NOT added here; use 'poetry run' or 'poetry shell'.
ARG HOME=/home/$USERNAME
ENV HOME=$HOME \
    PATH="$HOME/.local/bin:$PATH" \
    R_LIBS_USER=$HOME/R/library

WORKDIR /home/${USERNAME}

# --- Development Environment Ready ---
# Keep container running for VS Code to attach
#CMD ["sleep", "infinity"]