#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mInstalling ROS Humble\e[0m"

locale-gen en_GB en_GB.UTF-8
update-locale LC_ALL=en_GB.UTF-8 LANG=en_GB.UTF-8
export LANG=en_GB.UTF-8

add-apt-repository universe

curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null

apt-get -y update
apt-get -y upgrade

apt-get -y install ros-humble-desktop ros-dev-tools ros-humble-xacro ros-humble-image-transport-plugins

echo "source /opt/ros/humble/setup.bash" >> /etc/profile.d/90-turtlebot-ros-profile.sh
chmod 755 /etc/profile.d/90-turtlebot-ros-profile.sh
