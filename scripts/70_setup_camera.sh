#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mCamera setup\e[0m"

USERNAME="${USERNAME:-robot}"

set +u
source /etc/profile.d/90-turtlebot-ros-profile.sh
set -u

apt-get update
apt-get install -y python3-pip pipx git python3-jinja2 libboost-dev libgnutls28-dev openssl libtiff-dev pybind11-dev qtbase5-dev libqt5core5a libqt5widgets5 cmake python3-yaml python3-ply libglib2.0-dev libgstreamer-plugins-base1.0-dev
apt-get install -y ros-humble-camera-ros

mkdir -p /home/$USERNAME/turtlebot3_ws/src && cd /home/$USERNAME/turtlebot3_ws/src
git clone -b v0.5.2 https://github.com/raspberrypi/libcamera.git
cd libcamera
meson setup build --buildtype=release -Dpipelines=rpi/vc4,rpi/pisp -Dipas=rpi/vc4,rpi/pisp -Dv4l2=true -Dgstreamer=enabled -Dtest=false -Dlc-compliance=disabled -Dcam=disabled -Dqcam=disabled -Ddocumentation=disabled -Dpycamera=enabled
# ninja -C build -j 1
# ninja -C build install -j 1
ninja -C build
ninja -C build install
ldconfig

echo 'export LD_LIBRARY_PATH=/usr/local/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH' | tee -a /etc/profile.d/92-libcamera.sh

touch /home/$USERNAME/.setup_camera

chmod +x /home/$USERNAME/setup_scripts/setup_camera.sh

systemctl enable camera_setup.service




