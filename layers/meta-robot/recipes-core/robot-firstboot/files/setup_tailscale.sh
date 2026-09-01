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

# Connect using auth key from config if available
AUTHKEY_FILE="/etc/robot-config/tailscale_authkey"
if [[ -s "$AUTHKEY_FILE" ]]; then
    AUTHKEY=$(cat "$AUTHKEY_FILE")
    HOSTNAME_FLAG=""
    if [[ "$(cat /etc/robot-config/tailscale_use_hostname 2>/dev/null)" == "1" ]]; then
        HOSTNAME_FLAG="--hostname=${HOSTNAME}"
    fi
    echo "Connecting to Tailscale with auth key..."
    tailscale up --authkey="$AUTHKEY" $HOSTNAME_FLAG
    rm -f "$AUTHKEY_FILE"
else
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
fi

rm -f "/home/${USERNAME}/.setup_tailscale"
