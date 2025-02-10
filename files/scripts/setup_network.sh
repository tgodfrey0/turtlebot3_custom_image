#!/bin/bash
set -eux -o pipefail

source /etc/profile.d/91-net-vars-profile.sh

if [[ -f /home/robot/.setup_network ]]; then
  echo -e "\e[1;32mAdding network connection for $NETWORK_SSID\e[0m"

  sudo echo "network: {config: disabled}" | sudo tee -a /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null

  cat << EOF > /tmp/wifi_config.yaml
network:
    ethernets:
        eth0:
            dhcp4: true
            optional: true
    version: 2
    wifis:
      wlan0:
        access-points:
          "$NETWORK_SSID":
            password: "$NETWORK_PASSWORD"
        dhcp4: true
        dgcp6:true
EOF

  # Merge the new configuration with the existing one
  sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
  sudo cp /tmp/wifi_config.yaml /etc/netplan/50-cloud-init.yaml
  # sudo sed -i '/wifis:/,/^[^ ]/!b; /^[^ ]/i\    wlan0:\n      access-points:\n        "'$NETWORK_SSID'":\n          password: "'$NETWORK_PASSWORD'"\n      dhcp4: true' /etc/netplan/50-cloud-init.yaml

fi
