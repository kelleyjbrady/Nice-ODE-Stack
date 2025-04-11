FROM nvidia/cuda:12.4.1-base-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
   
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
        g++ \
        graphviz \
        git \
        wget \
        curl \
        vim \
        nano \
        build-essential \
        software-properties-common \
        # R base, development tools, and common R package dependencies
        r-base \
        r-base-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libfontconfig1-dev \
        libcairo2-dev \
        libxt-dev \
    # Clean up apt caches
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

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
 pip3 install --no-cache-dir poetry ruff radian

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
WORKDIR /workspaces/poetry-env

# Copy only dependency definition files first to leverage Docker cache
COPY pyproject.toml poetry.lock* ./

# Install project dependencies using Poetry
# --no-interaction: Do not ask interactive questions
# --no-ansi: Produce plain output
# --no-root: Skip installing the project package itself (if it's an app, not a library)
# This command creates the virtualenv based on POETRY_VIRTUALENVS_PATH
RUN poetry install --no-interaction --no-ansi --no-root --no-cache

# Copy the rest of the application source code
COPY . .

# --- User Setup ---
ARG USERNAME=vscode
# Create the user group and user; -m creates the home directory
# Also add user to video group for potential GPU access outside CUDA-specific tasks (optional)
RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME #&& \

# Grant ownership of the app directory and the venvs to the user
# This allows the user to manage files and potentially install packages later if needed
RUN chown -R $USERNAME:$USER_GID /workspaces/poetry-env ${POETRY_VIRTUALENVS_PATH}


# Switch context to the non-root user
USER $USERNAME

# Set home environment variable and update PATH for user's local bin and poetry
# Note: The poetry executable itself should now be accessible via the inherited PATH
# or we can explicitly add the expected user location if needed.
# The venv path is NOT added here; use 'poetry run' or 'poetry shell'.
ENV HOME=/home/$USERNAME \
    PATH="$HOME/.local/bin:$PATH" \
    R_LIBS_USER=$HOME/R/library

WORKDIR /workspaces/poetry-env

# --- Development Environment Ready ---
# Keep container running for VS Code to attach
CMD ["sleep", "infinity"]