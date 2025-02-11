#!/bin/bash
set -eux -o pipefail

source /etc/profile.d/90-turtlebot-ros-profile.sh

ros2 launch turtlebot3_bringup robot.launch.py
