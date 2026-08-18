#!/bin/bash
# TurtleBot3 robot plugin - step 40: OpenCR setup
set -eux -o pipefail

USERNAME="${USERNAME:-robot}"
export OPENCR_PORT=/dev/ttyACM0

# Copy robot-specific runtime scripts into place
mkdir -p /home/$USERNAME/setup_scripts
cp /tmp/robot_plugin/setup_scripts/setup_opencr.sh /home/$USERNAME/setup_scripts/setup_opencr.sh
chmod +x /home/$USERNAME/setup_scripts/setup_opencr.sh

dpkg --add-architecture armhf
apt-get -y update
apt-get -y install libc6:armhf

rm -rf ./opencr_update.tar.bz2

cd /home/$USERNAME/
wget https://github.com/ROBOTIS-GIT/OpenCR-Binaries/raw/master/turtlebot3/ROS2/latest/opencr_update.tar.bz2
tar -xvf ./opencr_update.tar.bz2

touch /home/$USERNAME/.setup_opencr
chmod +x /home/$USERNAME/setup_scripts/setup_opencr.sh
systemctl enable opencr_setup.service

# Set up bringup service (not auto-enabled, user must enable manually)
chmod +x /home/$USERNAME/setup_scripts/bringup.sh