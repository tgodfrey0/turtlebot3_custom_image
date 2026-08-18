#!/bin/bash
set -eux -o pipefail

# Skip Tailscale installation if disabled
if [ "${TAILSCALE_ENABLED:-true}" != "true" ]; then
    echo -e "\e[1;33mTailscale installation skipped (TAILSCALE_ENABLED=false)\e[0m"
    exit 0
fi

echo -e "\e[1;32mInstalling Tailscale\e[0m"

curl -fsSL https://tailscale.com/install.sh | sh

# If an auth key is provided, write it for first-boot service
if [ -n "${TAILSCALE_AUTH_KEY:-}" ]; then
    USERNAME="${USERNAME:-robot}"
    mkdir -p /home/$USERNAME/.config
    echo "$TAILSCALE_AUTH_KEY" > /home/$USERNAME/.config/tailscale_auth_key
    chown $USERNAME:$USERNAME /home/$USERNAME/.config/tailscale_auth_key
    chmod 600 /home/$USERNAME/.config/tailscale_auth_key

    # Enable first-boot Tailscale service
    touch /home/$USERNAME/.setup_tailscale
    chmod +x /home/$USERNAME/setup_scripts/setup_tailscale.sh
    systemctl enable tailscale_setup.service
fi
