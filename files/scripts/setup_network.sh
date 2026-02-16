#!/bin/bash
set -eux -o pipefail

USERNAME="${USERNAME}"
NETWORKS_FILE="/home/$USERNAME/.config/networks.json"

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

    # Parse networks and add to netplan config using Python
    python3 << PYTHON_SCRIPT
import json

networks_file = "/home/$USERNAME/.config/networks.json"
netplan_file = "/etc/netplan/50-cloud-init.yaml"

with open(networks_file, 'r') as f:
    networks = json.load(f)

with open(netplan_file, 'a') as f:
    for net in networks:
        ssid = net.get('ssid', '')
        password = net.get('password', '')
        if ssid:
            if password:
                f.write(f'          "{ssid}":\n')
                f.write(f'            password: "{password}"\n')
            else:
                f.write(f'          "{ssid}":\n')
                f.write(f'            auth:\n')
                f.write(f'              key-management: none\n')
    
    f.write('        dhcp4: true\n')
    f.write('        dhcp6: true\n')

print("Network configuration written successfully")
PYTHON_SCRIPT

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
