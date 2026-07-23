FROM nvidia/cuda:12.4.1-base-ubuntu22.04

LABEL org.opencontainers.image.source="https://github.com/NiceODE-LLC/NiceODE"
LABEL org.opencontainers.image.description="Base CUDA 12.4 environment with Python 3.13.14, R 4.6.1, and Julia 1.12.6"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    # --- Locale Settings ---
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    # Set user/group IDs
    USER_UID=1000 \
    USER_GID=1000 \
    # Disable virtualenv creation in project directory, store centrally
    POETRY_VIRTUALENVS_IN_PROJECT=false \
    POETRY_VIRTUALENVS_PATH=/opt/poetry-venvs \
    # Allow the global system library to pass through the renv sandbox (for VS Code tools)
    RENV_CONFIG_EXTERNAL_LIBRARIES=/usr/local/lib/R/site-library \
    # Add poetry bin to PATH for root during build and later for the user
    PATH="/root/.local/bin:$PATH"

# --- System Setup ---
# Install system dependencies: common utilities, build tools, and SVG support
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
        # --- Basic SVG & Image Rendering Support ---
        librsvg2-bin \
        libpng-dev \
        libfreetype6-dev \
        libjpeg-dev \
    # Add the CRAN GPG key and repository for Ubuntu 22.04 (Jammy)
    && wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc && \
    add-apt-repository 'deb https://cloud.r-project.org/bin/linux/ubuntu jammy-cran40/' && \
    # Update apt lists again and install strictly pinned R and its dependencies
    apt-get update && \
    apt-get install -y --no-install-recommends \
        r-base=4.6.1-* \
        r-base-dev=4.6.1-* \
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
        libuv1-dev \
    # Clean up apt caches to reduce image size
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Generate Locale ---
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

# --- Python Setup ---
# Add deadsnakes PPA and strictly pin Python 3.13 to the current patch level
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    # Add the deadsnakes PPA
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \   
        python3.13=3.13.14-* \
        python3.13-dev=3.13.14-* \
        python3.13-venv=3.13.14-* && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Update alternatives to make python3 point to python3.13
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 2 && \
    update-alternatives --set python3 /usr/bin/python3.13

# Ensure pip is linked, install specific version of Poetry
RUN python3 -m ensurepip --upgrade && \
    pip3 install --no-cache-dir --upgrade pip && \
 pip3 install --no-cache-dir poetry==2.4.*
 # Optional: Add completions globally
RUN mkdir -p /etc/bash_completion.d && \
    poetry completions bash > /etc/bash_completion.d/poetry.bash

# --- Julia Setup ---
# Download and install Julia from official binaries
RUN cd /tmp && \
    wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.12/julia-1.12.6-linux-x86_64.tar.gz && \
    tar -xzf julia-1.12.6-linux-x86_64.tar.gz -C /opt/ && \
    ln -s /opt/julia-1.12.6/bin/julia /usr/local/bin/julia && \
    rm julia-1.12.6-linux-x86_64.tar.gz && \
    # Verify installation
    julia --version

#-----Quarto Setup-----
ARG QUARTO_VERSION="1.9.38" 
RUN cd /tmp && \
    curl -LO https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb && \
    # apt-get install locally resolves missing lightweight OS dependencies
    apt-get install -y --no-install-recommends ./quarto-${QUARTO_VERSION}-linux-amd64.deb && \
    rm quarto-${QUARTO_VERSION}-linux-amd64.deb && \
    quarto check

# --- Global R Setup ---
RUN R -e "install.packages('remotes', repos = 'https://cloud.r-project.org/')"

COPY r_requirements.csv install_R_pkgs.R /tmp/
RUN cd /tmp && Rscript install_R_pkgs.R && \
    rm /tmp/r_requirements.csv /tmp/install_R_pkgs.R

ENV RENV_PATHS_CACHE=/opt/renv/cache
RUN mkdir -p ${RENV_PATHS_CACHE} && \
    chown -R ${USER_UID}:${USER_GID} /opt/renv

# --- Application Setup (as root for installation) ---
ARG DEV_TOOLS_PROJ_PATH=/workspaces/cuda-py-dev-tools
WORKDIR $DEV_TOOLS_PROJ_PATH

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
#COPY .Rprofile /home/${USERNAME}/.Rprofile

# Ensure the .Rprofile is owned by the user
#RUN chown ${USERNAME}:${USER_GID} /home/${USERNAME}/.Rprofile


# Install dev tools dependencies using Poetry
# --no-interaction: Do not ask interactive questions
# --no-ansi: Produce plain output
# --no-root: Skip installing the project package itself (if it's an app, not a library)
# This command creates the virtualenv based on POETRY_VIRTUALENVS_PATH
RUN poetry install --no-interaction --no-ansi --no-root --no-cache

# --- Make tools from the dev tools venv easily accessible ---
RUN DEV_TOOLS_VENV_PATH=$(poetry env info --path) && \
    echo "export PATH=\"${DEV_TOOLS_VENV_PATH}/bin:\$PATH\"" >> /etc/bash.bashrc && \
    echo "export PATH=\"${DEV_TOOLS_VENV_PATH}/bin:\$PATH\"" > /etc/profile.d/dev_tools_poetry_env.sh && \
    chmod +x /etc/profile.d/dev_tools_poetry_env.sh && \
    rm -rf /build_env_tools

RUN chown -R $USERNAME:$USER_GID ${DEV_TOOLS_PROJ_PATH} ${POETRY_VIRTUALENVS_PATH}

# --- Switch context to the non-root user ---
USER $USERNAME

ARG HOME=/home/$USERNAME
ENV HOME=$HOME \
    PATH="$HOME/.local/bin:$PATH" \
    R_LIBS_USER=$HOME/R/library

WORKDIR /home/${USERNAME}