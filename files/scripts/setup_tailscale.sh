#!/bin/bash
set -eux -o pipefail

read USERNAME < /etc/robot-user

if [[ ! -f /home/${USERNAME}/.setup_tailscale ]]; then
    exit 0
fi

echo "Configuring Tailscale..."

AUTH_KEY_FILE="/home/${USERNAME}/.config/tailscale_auth_key"
HOSTNAME=$(hostname)

if [[ -f "$AUTH_KEY_FILE" ]]; then
    AUTH_KEY=$(cat "$AUTH_KEY_FILE")
    sudo tailscale up --authkey="$AUTH_KEY" --hostname="$HOSTNAME"
    rm -f "$AUTH_KEY_FILE"
else
    echo "No auth key found. Run 'tailscale up' manually to authorize."
fi

rm -f "/home/${USERNAME}/.setup_tailscale"
