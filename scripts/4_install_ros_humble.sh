#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mInstalling ROS Humble\e[0m"

locale  # check for UTF-8

apt-get update && apt-get install locales
locale-gen en_US en_US.UTF-8
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

locale  # verify settings

apt-get install software-properties-common
add-apt-repository universe

apt-get update && apt-get install curl -y
curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null

apt-get update
apt-get upgrade

apt-get install ros-humble-desktop
apt-get install ros-dev-tools

echo "source /opt/ros/humble/setup.bash" >> /etc/profile.d/90-turtlebot-ros-profile.sh