#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mOpenCR setup\e[0m"

dpkg --add-architecture armhf
apt-get -y update
apt-get -y install libc6:armhf

export OPENCR_PORT=/dev/ttyACM0
rm -rf ./opencr_update.tar.bz2

cd /home/robot/
wget https://github.com/ROBOTIS-GIT/OpenCR-Binaries/raw/master/turtlebot3/ROS2/latest/opencr_update.tar.bz2
tar -xvf ./opencr_update.tar.bz2

touch /home/robot/.setup_opencr

chmod +x /home/robot/setup_scripts/setup_opencr.sh

systemctl enable opencr_setup.service
