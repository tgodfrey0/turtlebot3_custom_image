#!/bin/bash
set -eux -o pipefail

if [[ -f /root/.setup_network ]]; then
  echo -e "\e[1;32mAdding network connection for $SSID\e[0m"
  cat << EOF > /tmp/wifi_config.yaml
  network:
    version: 2
    wifis:
      wlan0:
        access-points:
          "$NETWORK_SSID":
            password: "$NETWORK_PASSWORD"
        dhcp4: true
EOF

  # Merge the new configuration with the existing one
  sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
  sudo sed -i '/wifis:/,/^[^ ]/!b; /^[^ ]/i\    wlan0:\n      access-points:\n        "'$NETWORK_SSID'":\n          password: "'$NETWORK_PASSWORD'"\n      dhcp4: true' /etc/netplan/50-cloud-init.yaml

fi
