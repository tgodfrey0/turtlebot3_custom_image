#!/bin/bash
set -eux -o pipefail

#!/bin/bash

if [[ "$ADD_CONNECTION" == "true" ]]; then
  echo -e "\e[1;32mAdding connection\e[0m"
  wireless_interface=$(ip link show | grep -E 'wlan|wlp|wifi' | awk -F': ' '{print $2}' | tr -d ' ' | head -n 1)
  if [ -z "$wireless_interface" ]; then
      echo "No wireless interface found"
      exit 1
  fi

  nmcli --offline connection add type wifi con-name "$CONNECTION_NAME" wifi.ssid $SSID wifi-sec.psk $PASSWORD
  nmcli con add type wifi ifname "$wireless_interface" con-name "$SSID" ssid "$SSID" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PASSWORD"

fi
