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
# Only treat Tailscale as configured when the backend is running and a real
# tailnet identity is present; otherwise we must still attempt the auth-key
# login flow.
if python3 - <<'PY'
import json
import subprocess
import sys

try:
    status = json.loads(
        subprocess.check_output(['tailscale', 'status', '--json'], stderr=subprocess.DEVNULL)
    )
except Exception:
    sys.exit(1)

backend_state = status.get('BackendState')
self_info = status.get('Self')
current_tailnet = status.get('CurrentTailnet')

if backend_state == 'Running' and (self_info or current_tailnet):
    sys.exit(0)

sys.exit(1)
PY
then
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
    tailscale up --ssh --authkey="file:/etc/robot-config/tailscale_authkey" "${HOSTNAME_ARGS[@]}"
else
    echo ""
    echo "============================================="
    echo "  Tailscale is not configured."
    echo "  To connect, run one of:"
    echo ""
    echo "    tailscale up --ssh                    # Interactive login"
    echo "    tailscale up --ssh --authkey=tskey-auth-...  # With auth key"
    echo ""
    echo "  Auth keys: https://login.tailscale.com/admin/settings/keys"
    echo "============================================="
    echo ""
fi

rm -f "/home/${USERNAME}/.setup_tailscale"
