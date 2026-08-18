#!/bin/bash
# TurtleBot3 robot plugin - step 10: build the colcon workspace
set -eux -o pipefail

ROS_DISTRO="${ROS_DISTRO:-humble}"
USERNAME="${USERNAME:-robot}"

# Source ROS and build workspace
cd "/home/$USERNAME/colcon_ws/"
echo "source /opt/ros/${ROS_DISTRO}/setup.bash" | tee -a /etc/profile.d/90-ros-profile.sh > /dev/null
set +u
source /etc/profile.d/90-ros-profile.sh
set -u
colcon build --symlink-install --parallel-workers 1
echo "source /home/$USERNAME/colcon_ws/install/setup.bash" | tee -a /etc/profile.d/90-ros-profile.sh > /dev/null
set +u
source /etc/profile.d/90-ros-profile.sh
set -u

chmod 755 "/home/$USERNAME/colcon_ws/install"/*