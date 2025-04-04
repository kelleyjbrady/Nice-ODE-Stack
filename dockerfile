# Use the official NVIDIA CUDA base image matching your CUDA 12.4 requirement
FROM nvidia/cuda:12.4.1-base-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    #PYTHON_VERSION=3.13.2 \
    # Set user/group IDs
    USER_UID=1000 \
    USER_GID=1000 \
    # Poetry config
    #POETRY_VERSION=2.1 \
    # Disable virtualenv creation in project directory, store centrally
    POETRY_VIRTUALENVS_IN_PROJECT=false \
    POETRY_VIRTUALENVS_PATH=/opt/poetry-venvs \
    # Add poetry bin to PATH for root during build and later for the user
    # Note: Installer puts it in .local/bin for the executing user (root here)
    PATH="/root/.local/bin:$PATH"

# --- System Setup ---
# Install system dependencies: Python, pip, git, common utilities, and build tools
# Removed python3-venv as Poetry handles environments
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        #python${PYTHON_VERSION} \
        #python3-pip \
        # python${PYTHON_VERSION}-venv # Removed
        git \
        wget \
        curl \
        vim \
        nano \
        build-essential \
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
        python3.13-venv && \
        #python3.13-setuptools \
        #python3.13-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Update alternatives to make python3 point to python3.13 (optional)
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 2 && \
    update-alternatives --set python3 /usr/bin/python3.13

# Ensure pip is correctly linked or use python3.13 -m pip
RUN python3 -m ensurepip --upgrade


RUN apt-get update && \
    apt-get install -y --no-install-recommends pipx && \
    pipx ensurepath 
    # && \
    #sudo pipx ensurepath --global # optional to allow pipx actions with --global argument

RUN pipx install poetry 
RUN poetry completions bash >> ~/.bash_completion
RUN pipx install ruff

# Upgrade pip & install Poetry
RUN pip3 install --no-cache-dir --upgrade pip


# --- Application Setup (as root for installation) ---
# Set a work directory for the application build steps
WORKDIR /app

# Copy only dependency definition files first to leverage Docker cache
COPY pyproject.toml poetry.lock* ./

# Install project dependencies using Poetry
# --no-interaction: Do not ask interactive questions
# --no-ansi: Produce plain output
# --no-root: Skip installing the project package itself (if it's an app, not a library)
# This command creates the virtualenv based on POETRY_VIRTUALENVS_PATH
RUN poetry install --no-interaction --no-ansi --no-root

# Copy the rest of the application source code
COPY . .

# --- User Setup ---
ARG USERNAME=vscode
# Create the user group and user; -m creates the home directory
# Also add user to video group for potential GPU access outside CUDA-specific tasks (optional)
RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME #&& \
    # Optionally add user to groups like 'video' if needed:
    # usermod -aG video $USERNAME

# Grant ownership of the app directory and the venvs to the user
# This allows the user to manage files and potentially install packages later if needed
# Note: Giving write access to /opt/poetry-venvs might be broad; adjust if needed.
RUN chown -R $USERNAME:$USER_GID /app ${POETRY_VIRTUALENVS_PATH}

# --- OPTIONAL: Grant sudo privileges ---
# (Keep the commented block as in the original if desired)
# RUN apt-get update && apt-get install -y sudo && ...

# Switch context to the non-root user
USER $USERNAME

# Set home environment variable and update PATH for user's local bin and poetry
# Note: The poetry executable itself should now be accessible via the inherited PATH
# or we can explicitly add the expected user location if needed.
# The venv path is NOT added here; use 'poetry run' or 'poetry shell'.
ENV HOME=/home/$USERNAME \
    PATH="$HOME/.local/bin:$PATH"

# Set the final working directory for the user
WORKDIR $HOME/workspace
# If your code stays in /app and you mount your local code there, use:
# WORKDIR /app

# --- Development Environment Ready ---
# Keep container running for VS Code to attach
CMD ["sleep", "infinity"]