#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mCamera setup\e[0m"

touch /home/robot/.setup_camera

chmod +x /home/robot/setup_scripts/setup_camera.sh

systemctl enable camera_setup.service
