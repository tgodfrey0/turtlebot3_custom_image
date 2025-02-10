#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mInstalling hostname service\e[0m"

touch /home/robot/.setup_hostname

chmod +x /home/robot/setup_scripts/setup_hostname.sh

systemctl enable hostname_setup.service
