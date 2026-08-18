#!/bin/bash
set -eux -o pipefail

USERNAME="${USERNAME:-robot}"
TAILSCALE_ENABLED="${TAILSCALE_ENABLED:-true}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"

echo -e "\e[1;32mUpdating Packages\e[0m"
apt-get -y update
apt-get -y auto-remove

# Install common packages for all robots (overridable list from config/env)
COMMON_PACKAGES="${COMMON_PACKAGES:-git curl ssh nano ffmpeg openssh-server locales pip software-properties-common meson ninja-build}"
apt-get -y install ${COMMON_PACKAGES}

# --- pixi (package/environment manager) -------------------------------------
# pixi is not shipped in the apt repos; install via its official installer.
export HOME="/home/$USERNAME"
if [ ! -x "$HOME/.pixi/bin/pixi" ]; then
    echo -e "\e[1;32mInstalling pixi (package manager)\e[0m"
    curl -fsSL https://pixi.sh/install.sh | bash
fi
ln -sf "$HOME/.pixi/bin/pixi" /usr/local/bin/pixi

# --- Rust via rustup (not the apt rustc/cargo, which can be outdated) -------
if [ ! -x "$HOME/.cargo/bin/rustc" ]; then
    echo -e "\e[1;32mInstalling Rust (rustup)\e[0m"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi

# Ensure pixi/Rust toolchains are usable via the default PATH
cat >> "$HOME/.bashrc" <<'EOF'

# pixi
export PATH="$HOME/.pixi/bin:$PATH"
# Rust (rustup)
export PATH="$HOME/.cargo/bin:$PATH"
EOF
chown -R "$USERNAME:$USERNAME" "$HOME/.pixi" "$HOME/.cargo" 2>/dev/null || true

# --- Tailscale (via official installer) -------------------------------------
if [ "$TAILSCALE_ENABLED" != "true" ]; then
    echo -e "\e[1;33mTailscale installation skipped (TAILSCALE_ENABLED=false)\e[0m"
else
    echo -e "\e[1;32mInstalling Tailscale\e[0m"
    curl -fsSL https://tailscale.com/install.sh | sh

    # If an auth key is provided, write it for first-boot service
    if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        mkdir -p /home/$USERNAME/.config
        echo "$TAILSCALE_AUTH_KEY" > /home/$USERNAME/.config/tailscale_auth_key
        chown $USERNAME:$USERNAME /home/$USERNAME/.config/tailscale_auth_key
        chmod 600 /home/$USERNAME/.config/tailscale_auth_key

        # Enable first-boot Tailscale service
        touch /home/$USERNAME/.setup_tailscale
        chmod +x /home/$USERNAME/setup_scripts/setup_tailscale.sh
        systemctl enable tailscale_setup.service
    fi
fi