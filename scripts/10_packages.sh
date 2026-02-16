#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mUpdating Packages\e[0m"
apt-get -y update
apt-get -y upgrade
apt-get -y auto-remove
apt-get -y install git curl ssh nano ffmpeg openssh-server locales pip software-properties-common

pip3 install --no-input uuid meson ninja
echo 'export PATH="/root/.local/bin:$PATH"' | tee -a /etc/profile.d/90-turtlebot-ros-profile.sh

