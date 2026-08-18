#!/bin/bash
set -ux -o pipefail

# Exit handler for diagnostics
trap 'rc=$?; echo "[hostname_setup] exited with code $rc" >&2; exit $rc' EXIT

read USERNAME < /etc/turtlebot3-user || { echo "Failed to read /etc/turtlebot3-user" >&2; exit 1; }

if [[ ! -f /home/${USERNAME}/.setup_hostname ]]; then
    exit 0
fi

# Get hostname from Python script; fall back to MAC-based name if it fails
NEW_HOSTNAME=""
if command -v python3 &>/dev/null; then
    NEW_HOSTNAME=$(python3 /home/${USERNAME}/setup_scripts/get_hostname.py 2>/dev/null) || NEW_HOSTNAME=""
fi
if [[ -z "$NEW_HOSTNAME" ]]; then
    # Fallback: read MAC from eth0 via sysfs
    if [[ -f /sys/class/net/eth0/address ]]; then
        MAC=$(tr -d ':' < /sys/class/net/eth0/address)
        NEW_HOSTNAME="tb3-${MAC: -6}"
    else
        NEW_HOSTNAME="tb3-robot"
    fi
fi

echo "Setting hostname to $NEW_HOSTNAME"
sed -i 's/preserve_hostname: false/preserve_hostname: true/' /etc/cloud/cloud.cfg 2>/dev/null || true

if command -v hostnamectl &>/dev/null; then
    hostnamectl set-hostname "$NEW_HOSTNAME" || echo "hostnamectl failed, using hostname command" >&2
else
    hostname "$NEW_HOSTNAME"
fi

rm -f "/home/${USERNAME}/.setup_hostname"
