#!/bin/bash
set -eux -o pipefail

read USERNAME < /etc/robot-user

if [[ ! -f /home/${USERNAME}/.setup_tailscale ]]; then
    exit 0
fi

echo "Configuring Tailscale..."

# Ensure tailscaled is running
if ! systemctl is-active --quiet tailscaled; then
    sudo systemctl start tailscaled
    sleep 2
fi

HOSTNAME=$(hostname)

# Check if already connected
if tailscale status &>/dev/null; then
    echo "Tailscale already configured."
    rm -f "/home/${USERNAME}/.setup_tailscale"
    exit 0
fi

echo ""
echo "============================================="
echo "  Tailscale is not configured."
echo "  To connect, run one of:"
echo ""
echo "    tailscale up                          # Interactive login"
echo "    tailscale up --authkey=tskey-auth-...  # With auth key"
echo ""
echo "  Auth keys: https://login.tailscale.com/admin/settings/keys"
echo "============================================="
echo ""

rm -f "/home/${USERNAME}/.setup_tailscale"
