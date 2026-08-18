#!/bin/bash
# TurtleBot3 robot plugin - step 00: install ROS packages and clone repos
set -eux -o pipefail

LIDAR="${LIDAR:-LDS-02}"
ROS_DISTRO="${ROS_DISTRO:-humble}"
ROBOT_MODEL="${ROBOT_MODEL:-burger}"
USERNAME="${USERNAME:-robot}"

# Write model config for runtime scripts
echo "$ROBOT_MODEL" > /etc/robot-config/robot_model

# Install the additional TurtleBot3-specific ROS packages (common packages
# such as git are installed globally by scripts/10_packages.sh).
_TB3_PKGS="python3-argcomplete python3-colcon-common-extensions libboost-system-dev build-essential ros-${ROS_DISTRO}-hls-lfcd-lds-driver ros-${ROS_DISTRO}-turtlebot3-msgs ros-${ROS_DISTRO}-dynamixel-sdk libudev-dev"
apt-get --simulate install ${_TB3_PKGS} > /dev/null 2>&1
apt-get -y install ${_TB3_PKGS}
unset _TB3_PKGS

# Clone TurtleBot3 and related repos
mkdir -p "/home/$USERNAME/colcon_ws/src" && cd "/home/$USERNAME/colcon_ws/src"
git clone -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/turtlebot3.git
git clone -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/ld08_driver.git
git clone -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/coin_d4_driver

# Remove navigation/cartographer (not needed for basic bringup)
cd "/home/$USERNAME/colcon_ws/src/turtlebot3"
rm -r turtlebot3_cartographer turtlebot3_navigation2