#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mInstalling hostname service\e[0m"

USERNAME="${USERNAME:-robot}"

touch /home/$USERNAME/.setup_hostname

chmod +x /home/$USERNAME/setup_scripts/setup_hostname.sh

systemctl enable hostname_setup.service
