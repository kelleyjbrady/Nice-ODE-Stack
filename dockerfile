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
# Install system dependencies: common utilities, build tools, SVG/R build libs, and Posit R 4.6.1
ARG R_VERSION=4.6.1
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # Locales package
        locales \
        # Compilers and build tools
        g++ \
        build-essential \
        cmake \
        ccache \
        ninja-build \
        gdb \
        strace \
        # Common utilities
        graphviz \
        git \
        wget \
        curl \
        ca-certificates \
        vim \
        nano \
        ripgrep \
        fd-find \
        bat \
        fzf \
        jq \
        tree \
        tmux \
        ncdu \
        htop \
        nvtop \
        rsync \
        pigz \
        unzip \
        # --- Basic SVG & Image Rendering Support ---
        librsvg2-bin \
        libpng-dev \
        libfreetype6-dev \
        libjpeg-dev \
        # R package build dependencies
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
    # Install exact R version from Posit precompiled .deb (immune to CRAN apt repo drift)
    && curl -fsSL -o /tmp/r-${R_VERSION}.deb "https://cdn.posit.co/r/ubuntu-2204/pkgs/r-${R_VERSION}_1_amd64.deb" && \
    apt-get install -y --no-install-recommends /tmp/r-${R_VERSION}.deb && \
    ln -sf /opt/R/${R_VERSION}/bin/R /usr/local/bin/R && \
    ln -sf /opt/R/${R_VERSION}/bin/Rscript /usr/local/bin/Rscript && \
    rm -f /tmp/r-${R_VERSION}.deb && \
    # Clean up apt caches to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Generate Locale ---
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen && \
    printf '\nalias fd=fdfind\nalias bat=batcat\neval "$(zoxide init bash)"\n' >> /etc/bash.bashrc

# --- Modern Navigation Tools (eza, zoxide) ---
ARG EZA_VERSION=0.20.10
ARG ZOXIDE_VERSION=0.9.6
RUN ARCH=$(dpkg --print-architecture) && \
    EZA_ARCH=$([ "$ARCH" = "amd64" ] && echo "x86_64" || echo "aarch64") && \
    curl -fsSL "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" | tar -xz -C /usr/local/bin && \
    ZOXIDE_ARCH=$([ "$ARCH" = "amd64" ] && echo "x86_64" || echo "aarch64") && \
    curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-${ZOXIDE_ARCH}-unknown-linux-musl.tar.gz" | tar -xz -C /usr/local/bin zoxide

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
    uv pip install --no-cache --python "$PYTHON_BIN" --break-system-packages pip poetry==2.4.* && \
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
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    quarto check

# --- Global R Bootstrap (remotes + renv only; r_requirements.csv runs after renv::restore) ---
RUN R -e "install.packages('remotes', repos = 'https://cloud.r-project.org/'); remotes::install_version('renv', version = '1.2.3', repos = 'https://cloud.r-project.org/', upgrade = 'never')"

# ---- User & Directory Setup (before installing caches/venvs to avoid OverlayFS chown copy-up) ----
ARG USERNAME=vscode
ARG DEV_TOOLS_PROJ_PATH=/workspaces/cuda-py-dev-tools
ARG PROJECT_PATH=/workspaces/PK-Analysis
ENV RENV_PATHS_CACHE=/opt/renv/cache \
    HOME=/home/${USERNAME} \
    R_LIBS_USER=/home/${USERNAME}/R/library

RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME && \
    mkdir -p ${RENV_PATHS_CACHE} ${POETRY_VIRTUALENVS_PATH} ${DEV_TOOLS_PROJ_PATH} ${PROJECT_PATH} \
             ${HOME}/R/library ${HOME}/.gemini/antigravity-cli && \
    chown -R ${USER_UID}:${USER_GID} /opt/renv ${POETRY_VIRTUALENVS_PATH} ${DEV_TOOLS_PROJ_PATH} ${PROJECT_PATH} ${HOME}

# --- Switch to non-root user so renv cache and Poetry venvs are owned by vscode on first write ---
USER $USERNAME
ENV PATH="${HOME}/.local/bin:$PATH"

# Pre-populate renv cache BEFORE global r_requirements.csv so all renv.lock packages (including knitr/rmarkdown/jsonlite deps) are cached.
# Also force-cache recommended packages whose system versions match renv.lock, then remove renv tarball staging cache.
COPY --chown=${USER_UID}:${USER_GID} renv.lock /tmp/renv.lock
RUN R -e "options(Ncpus = max(1, parallel::detectCores())); renv::restore(lockfile = '/tmp/renv.lock', library = tempdir(), exclude = 'spatial', prompt = FALSE); renv::install(c('class@7.3-23', 'nnet@7.3-20', 'Matrix@1.7-5'), library = tempdir(), rebuild = TRUE, prompt = FALSE)" && \
    rm -rf /tmp/renv.lock "${HOME}/.cache/R/renv"

# 1. Dev Tools Setup (radian, ruff, jupyterlab)
WORKDIR $DEV_TOOLS_PROJ_PATH
COPY --chown=${USER_UID}:${USER_GID} pyproject.dev-tools.toml ./pyproject.toml
RUN poetry install --no-interaction --no-ansi --no-root --no-cache

# 2. Project Dependencies Pre-installation (PK-Analysis / niceode)
WORKDIR $PROJECT_PATH
COPY --chown=${USER_UID}:${USER_GID} pyproject.toml poetry.lock ./
RUN poetry install --no-interaction --no-ansi --no-root --no-cache

# 3. Install Antigravity CLI (agy) into $HOME/.local/bin
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# --- Brief root pass: install global VS Code/Quarto R tools and expose venv PATHs ---
USER root
COPY r_requirements.csv install_R_pkgs.R /tmp/
RUN cd /tmp && Rscript install_R_pkgs.R && \
    rm -f /tmp/r_requirements.csv /tmp/install_R_pkgs.R && \
    DEV_TOOLS_VENV_PATH=$(su -s /bin/bash ${USERNAME} -c "POETRY_VIRTUALENVS_PATH=${POETRY_VIRTUALENVS_PATH} poetry -C ${DEV_TOOLS_PROJ_PATH} env info --path") && \
    PROJECT_VENV_PATH=$(su -s /bin/bash ${USERNAME} -c "POETRY_VIRTUALENVS_PATH=${POETRY_VIRTUALENVS_PATH} poetry -C ${PROJECT_PATH} env info --path") && \
    echo "export PATH=\"${DEV_TOOLS_VENV_PATH}/bin:\$PATH\"" >> /etc/bash.bashrc && \
    echo "export PATH=\"${DEV_TOOLS_VENV_PATH}/bin:\$PATH\"" > /etc/profile.d/dev_tools_poetry_env.sh && \
    chmod +x /etc/profile.d/dev_tools_poetry_env.sh && \
    echo "export PATH=\"${PROJECT_VENV_PATH}/bin:\$PATH\"" >> /etc/bash.bashrc && \
    echo "export PATH=\"${PROJECT_VENV_PATH}/bin:\$PATH\"" > /etc/profile.d/project_poetry_env.sh && \
    chmod +x /etc/profile.d/project_poetry_env.sh

USER $USERNAME
WORKDIR /home/${USERNAME}