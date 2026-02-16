#!/bin/bash
set -eux -o pipefail

set +u
source /etc/profile.d/90-turtlebot-ros-profile.sh
set -u

ros2 launch turtlebot3_bringup robot.launch.py
