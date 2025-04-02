# Use the official NVIDIA CUDA base image matching your CUDA 12.4 requirement
FROM nvidia/cuda:12.4.1-base-ubuntu22.04

# Set environment variables to prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies: Python, pip, venv, git, and common utilities
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        git \
        wget \
        curl \
        vim \
        nano \
        build-essential \
    # Create python symlink for convenience (optional, but common)
    #&& ln -s /usr/bin/python3 /usr/bin/python \
    #&& ln -s /usr/bin/pip3 /usr/bin/pip \
    # Clean up apt caches to reduce image size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip

# Install JAX with CUDA 12 support
RUN pip install --no-cache-dir -U "jax[cuda12]"

# --- User Setup for VS Code Development ---
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user group and user; -m creates the home directory owned by the user
RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

# --- OPTIONAL: Grant sudo privileges ---
# Uncomment the following block if you want the 'vscode' user to have passwordless sudo access.
# This allows running 'sudo apt-get install ...' or 'sudo pip install ...' after launch.
# WARNING: This reduces the security benefit of running as a non-root user.
# RUN apt-get update && apt-get install -y sudo && \
#     # Add user to the sudo group (common practice)
#     adduser $USERNAME sudo && \
#     # Configure sudo to not require a password for members of the sudo group
#     echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
#     apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch context to the non-root user BEFORE setting user-specific ENV vars or WORKDIR
USER $USERNAME

# Set home environment variable (good practice, ensures tools find the home dir)
ENV HOME=/home/$USERNAME
# Add user's local bin directory (~/.local/bin) to PATH.
# This ensures executables installed via 'pip install --user' are found.
ENV PATH=$HOME/.local/bin:$PATH

# Set the default working directory inside the container
WORKDIR $HOME/workspace

# --- Development Environment Ready ---
# Keep container running for VS Code to attach
CMD ["sleep", "infinity"]