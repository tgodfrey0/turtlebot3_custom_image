#!/bin/bash
set -ux -o pipefail

trap 'rc=$?; echo "[hostname_setup] exited with code $rc" >&2; exit $rc' EXIT

read USERNAME < /etc/robot-user || { echo "Failed to read /etc/robot-user" >&2; exit 1; }

if [[ ! -f /home/${USERNAME}/.setup_hostname ]]; then
    exit 0
fi

HOSTNAME_PREFIX="robot"
if [[ -f /etc/robot-config/hostname_prefix ]]; then
    HOSTNAME_PREFIX=$(cat /etc/robot-config/hostname_prefix)
fi

NEW_HOSTNAME=""
if command -v python3 &>/dev/null; then
    NEW_HOSTNAME=$(python3 /home/${USERNAME}/setup_scripts/get_hostname.py 2>/dev/null) || NEW_HOSTNAME=""
fi
if [[ -z "$NEW_HOSTNAME" ]]; then
    if [[ -f /sys/class/net/eth0/address ]]; then
        MAC=$(tr -d ':' < /sys/class/net/eth0/address)
        # take last 6 hex chars and format as AA_BB_CC uppercase
        suffix_lower=${MAC: -6}
        s1=${suffix_lower:0:2}
        s2=${suffix_lower:2:2}
        s3=${suffix_lower:4:2}
        suffix="${s1}_${s2}_${s3}"
        suffix=$(echo "${suffix}" | tr '[:lower:]' '[:upper:]')
        NEW_HOSTNAME="${HOSTNAME_PREFIX}_${suffix}"
    else
        NEW_HOSTNAME="${HOSTNAME_PREFIX}_ROBOT"
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
