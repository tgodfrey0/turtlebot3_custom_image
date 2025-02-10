#!/bin/bash
set -eux -o pipefail


if [[ "$ADD_CONNECTION" == "true" ]]; then
  echo -e "\e[1;32mInstalling network service\e[0m"

  touch /home/robot/.setup_network

  chmod +x /home/robot/setup_scripts/setup_network.sh

  systemctl enable network_setup.service
else
  echo -e "\e[1;32mNot installing network service\e[0m"
fi
