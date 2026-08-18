#!/bin/bash
set -eux -o pipefail

read USERNAME < /etc/turtlebot3-user
NETWORKS_FILE="/home/$USERNAME/.config/networks.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$NETWORKS_FILE" ]]; then
    echo -e "\e[1;32mConfiguring WiFi networks from $NETWORKS_FILE\e[0m"

    # Disable cloud-init network configuration
    mkdir -p /etc/cloud/cloud.cfg.d/
    echo "network: {config: disabled}" | tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null

    # Create the base netplan configuration file
    cat > /etc/netplan/50-cloud-init.yaml << 'BASE_EOF'
network:
    ethernets:
        eth0:
            dhcp4: true
            optional: true
    version: 2
    renderer: networkd
    wifis:
      wlan0:
        access-points:
BASE_EOF

    # Generate netplan entries from stored networks
    python3 "$SCRIPT_DIR/gen_netplan.py" "$USERNAME"

    # Set proper permissions
    chmod 600 /etc/netplan/50-cloud-init.yaml
    
    # Apply the configuration
    netplan apply || echo "Netplan apply will take effect on next boot"
    
    # Remove the setup marker and config file
    rm -f "$NETWORKS_FILE"
    rm -f "/home/$USERNAME/.setup_network"
    
    echo -e "\e[1;32mWiFi networks configured successfully\e[0m"
else
    echo -e "\e[1;33mNo network configuration file found at $NETWORKS_FILE\e[0m"
fi
