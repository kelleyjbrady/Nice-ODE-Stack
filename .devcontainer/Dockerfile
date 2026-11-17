FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

ARG DEBIAN_FRONTEND=noninteractive

# Core CLI utilities from apt
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ripgrep \
        fd-find \
        bat \
        fzf \
        jq \
        tree \
        unzip \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Modern CLI binaries not available (or outdated) in Ubuntu 22.04 apt
ARG YQ_VERSION=4.44.3
ARG LAZYGIT_VERSION=0.44.1
ARG DELTA_VERSION=0.18.2
ARG EZA_VERSION=0.20.10
ARG ZOXIDE_VERSION=0.9.6

RUN ARCH=$(dpkg --print-architecture) && \
    # yq
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}" -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    # lazygit
    LAZYGIT_ARCH=$([ "$ARCH" = "amd64" ] && echo "x86_64" || echo "arm64") && \
    curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LAZYGIT_ARCH}.tar.gz" | tar -xz -C /usr/local/bin lazygit && \
    # git-delta
    curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH}.deb" -o /tmp/delta.deb && \
    dpkg -i /tmp/delta.deb && rm -f /tmp/delta.deb && \
    # eza
    EZA_ARCH=$([ "$ARCH" = "amd64" ] && echo "x86_64" || echo "aarch64") && \
    curl -fsSL "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" | tar -xz -C /usr/local/bin && \
    # zoxide
    ZOXIDE_ARCH=$([ "$ARCH" = "amd64" ] && echo "x86_64" || echo "aarch64") && \
    curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-${ZOXIDE_ARCH}-unknown-linux-musl.tar.gz" | tar -xz -C /usr/local/bin zoxide

# Global bash conveniences for Ubuntu-renamed tools and zoxide
RUN printf '\nalias fd=fdfind\nalias bat=batcat\neval "$(zoxide init bash)"\n' >> /etc/bash.bashrc
