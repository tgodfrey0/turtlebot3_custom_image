#!/bin/bash
set -eux -o pipefail

USERNAME="${USERNAME:-robot}"

if [[ "$ADD_CONNECTION" == "true" ]]; then
  echo -e "\e[1;32mInstalling network service\e[0m"

  touch /home/$USERNAME/.setup_network

  chmod +x /home/$USERNAME/setup_scripts/setup_network.sh

  systemctl enable network_setup.service
else
  echo -e "\e[1;32mNot installing network service\e[0m"
fi
