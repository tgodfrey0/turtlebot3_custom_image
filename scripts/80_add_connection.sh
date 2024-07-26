#!/bin/bash
set -eux -o pipefail

#!/bin/bash

if [[ "$ADD_CONNECTION" == "true" ]]; then
  echo -e "\e[1;32mAdding connection\e[0m"
  nmcli --offline connection add type $CONNECTION_TYPE con-name $CONNECTION_NAME ifname $INTERFACE wifi-ssid $SSID wifi-sec.psk $PASSWORD
fi

