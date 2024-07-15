#!/bin/bash

echo -e "\e[1;32mOpenCR setup\e[0m"

dpkg --add-architecture armhf
apt update
apt install libc6:armhf

export OPENCR_PORT=/dev/ttyACM0
export OPENCR_MODEL=waffle
rm -rf ./opencr_update.tar.bz2

wget https://github.com/ROBOTIS-GIT/OpenCR-Binaries/raw/master/turtlebot3/ROS2/latest/opencr_update.tar.bz2
tar -xvf ./opencr_update.tar.bz2

cd /root/opencr_update
./update.sh $OPENCR_PORT $OPENCR_MODEL.opencr