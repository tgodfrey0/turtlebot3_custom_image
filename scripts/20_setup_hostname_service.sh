#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mInstalling hostname service\e[0m"

touch /root/.set_hostname

chmod +x /root/set_hostname.sh

systemctl enable set_turtlebot_hostname.service
# systemctl start set_turtlebot_hostname.service
