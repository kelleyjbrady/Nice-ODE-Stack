FROM nvidia/cuda:12.4.1-base-ubuntu22.04

ARG GIT_COMMIT=unspecified
LABEL org.opencontainers.image.revision=$GIT_COMMIT
LABEL org.opencontainers.image.source="https://github.com/kelleyjbrady/Nice-ODE-Stack"
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
        # Pandoc and zlib for knitr, rmarkdown, haven, StanHeaders
        pandoc \
        zlib1g-dev \
    # Clean up apt caches to reduce image size
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Generate Locale ---
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

# --- Python Setup ---
# 1. Pull the compiled uv binary directly from Astral's official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
ENV UV_PYTHON_INSTALL_DIR=/opt/python

# 2. Download the exact patch and wire it into the system path
RUN uv python install 3.13.14 && \
    PYTHON_BIN=$(uv python find 3.13.14) && \
    ln -s "$PYTHON_BIN" /usr/local/bin/python3.13 && \
    ln -s "$PYTHON_BIN" /usr/local/bin/python3 && \
    ln -s "$PYTHON_BIN" /usr/local/bin/python

# 3. Use uv's installer to inject pip and poetry directly 
RUN PYTHON_BIN=$(uv python find 3.13.14) && \
    PYTHON_BIN_DIR=$(dirname "$PYTHON_BIN") && \
    # Explicitly bypass the PEP 668 lock since we are configuring the Docker base layer
    uv pip install --python "$PYTHON_BIN" --break-system-packages pip poetry==2.4.* && \
    # Symlink the newly installed tools so they are globally accessible
    ln -s "$PYTHON_BIN_DIR/pip3" /usr/local/bin/pip3 && \
    ln -s "$PYTHON_BIN_DIR/pip" /usr/local/bin/pip && \
    ln -s "$PYTHON_BIN_DIR/poetry" /usr/local/bin/poetry

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
RUN mkdir -p ${RENV_PATHS_CACHE}

# Pre-populate renv cache with all project dependencies from renv.lock
COPY renv.lock /tmp/renv.lock
RUN R -e "options(Ncpus = max(1, parallel::detectCores())); renv::restore(lockfile = '/tmp/renv.lock', library = tempdir(), prompt = FALSE)" && \
    rm /tmp/renv.lock

# --- Application Setup (as root for installation) ---
# 1. Dev Tools Setup (radian, ruff, jupyterlab)
ARG DEV_TOOLS_PROJ_PATH=/workspaces/cuda-py-dev-tools
WORKDIR $DEV_TOOLS_PROJ_PATH

COPY pyproject.dev-tools.toml ./pyproject.toml

# ---- User setup ----
ARG USERNAME=vscode
# Create the user group and user; -m creates the home directory
# Do this *before* creating user-owned directories
RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

# Create necessary directories needed by the user and set ownership *before* switching user
RUN mkdir -p ${POETRY_VIRTUALENVS_PATH} /home/${USERNAME}/R/library && \
    chown -R ${USERNAME}:${USER_GID} ${POETRY_VIRTUALENVS_PATH} /home/${USERNAME}/R /home/${USERNAME}/R/library

# Install dev tools dependencies using Poetry
RUN poetry install --no-interaction --no-ansi --no-root --no-cache

# --- Make tools from the dev tools venv easily accessible ---
RUN DEV_TOOLS_VENV_PATH=$(poetry env info --path) && \
    echo "export PATH=\"${DEV_TOOLS_VENV_PATH}/bin:\$PATH\"" >> /etc/bash.bashrc && \
    echo "export PATH=\"${DEV_TOOLS_VENV_PATH}/bin:\$PATH\"" > /etc/profile.d/dev_tools_poetry_env.sh && \
    chmod +x /etc/profile.d/dev_tools_poetry_env.sh

# 2. Project Dependencies Pre-installation (PK-Analysis / niceode)
ARG PROJECT_PATH=/workspaces/PK-Analysis
WORKDIR $PROJECT_PATH

COPY pyproject.toml poetry.lock ./
# Pre-install all project dependencies into /opt/poetry-venvs/
RUN poetry install --no-interaction --no-ansi --no-root --no-cache

# Expose project venv to PATH globally so python, pytest, etc. are immediately available
RUN PROJECT_VENV_PATH=$(poetry env info --path) && \
    echo "export PATH=\"${PROJECT_VENV_PATH}/bin:\$PATH\"" >> /etc/bash.bashrc && \
    echo "export PATH=\"${PROJECT_VENV_PATH}/bin:\$PATH\"" > /etc/profile.d/project_poetry_env.sh && \
    chmod +x /etc/profile.d/project_poetry_env.sh

# Ensure vscode user owns everything in virtualenvs and renv cache for mutability
RUN chown -R $USERNAME:$USER_GID ${DEV_TOOLS_PROJ_PATH} ${PROJECT_PATH} ${POETRY_VIRTUALENVS_PATH} /opt/renv

# --- Switch context to the non-root user ---
USER $USERNAME

ARG HOME=/home/$USERNAME
ENV HOME=$HOME \
    PATH="$HOME/.local/bin:$PATH" \
    R_LIBS_USER=$HOME/R/library

# Install Antigravity CLI (agy) into $HOME/.local/bin and pre-create config dir for volume mounts
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash && \
    mkdir -p $HOME/.gemini/antigravity-cli

WORKDIR /home/${USERNAME}