#!/bin/bash
set -eux -o pipefail

read USERNAME < /etc/robot-user
NETWORKS_FILE="/home/$USERNAME/.config/networks.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$NETWORKS_FILE" ]]; then
    echo -e "\e[1;32mConfiguring WiFi networks from $NETWORKS_FILE\e[0m"

    mkdir -p /etc/cloud/cloud.cfg.d/
    echo "network: {config: disabled}" | tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null

    cat > /etc/netplan/50-wifi.yaml << 'BASE_EOF'
network:
    ethernets:
        eth0:
            dhcp4: true
            optional: true
            nameservers:
                addresses: [8.8.8.8, 8.8.4.4]
    version: 2
    renderer: networkd
    wifis:
      wlan0:
        access-points:
BASE_EOF

    python3 "$SCRIPT_DIR/gen_netplan.py" "$USERNAME"

    chmod 600 /etc/netplan/50-wifi.yaml

    netplan apply || echo "Netplan apply will take effect on next boot"

    rm -f "/home/$USERNAME/.setup_network"

    echo -e "\e[1;32mWiFi networks configured successfully\e[0m"
else
    echo -e "\e[1;33mNo network configuration file found at $NETWORKS_FILE\e[0m"
fi
