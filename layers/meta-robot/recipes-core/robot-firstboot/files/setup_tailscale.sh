#!/bin/bash
set -eux -o pipefail

read USERNAME < /etc/robot-user

if [[ ! -f /home/${USERNAME}/.setup_tailscale ]]; then
    exit 0
fi

echo "Configuring Tailscale..."

# Ensure tailscaled is running and its control socket is ready.
systemctl start tailscaled
for _ in {1..30}; do
    if [[ -S /var/run/tailscale/tailscaled.sock ]]; then
        break
    fi
    sleep 1
done

HOSTNAME=$(hostname)

# `tailscale status` exits successfully even when the backend needs login.
# Check the reported backend state instead.
if tailscale status --json 2>/dev/null | grep -q '"BackendState":[[:space:]]*"Running"'; then
    echo "Tailscale already configured."
    rm -f "/home/${USERNAME}/.setup_tailscale"
    exit 0
fi

# Connect using auth key from config if available
AUTHKEY_FILE="/etc/robot-config/tailscale_authkey"
if [[ -s "$AUTHKEY_FILE" ]]; then
    AUTHKEY=$(cat "$AUTHKEY_FILE")
    HOSTNAME_ARGS=()
    if [[ "$(cat /etc/robot-config/tailscale_use_hostname 2>/dev/null)" == "1" ]]; then
        HOSTNAME_ARGS=(--hostname "$HOSTNAME")
    fi
    echo "Connecting to Tailscale with auth key from file..."
    tailscale up --authkey="file:/etc/robot-config/tailscale_authkey" "${HOSTNAME_ARGS[@]}"
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
