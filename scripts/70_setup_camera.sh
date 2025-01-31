#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mCamera setup\e[0m"

touch /root/.setup_camera

chmod +x /root/setup_scripts/setup_camera.sh

systemctl enable camera_setup.service
