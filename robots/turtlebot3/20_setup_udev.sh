#!/bin/bash
# TurtleBot3 robot plugin - step 20: install udev rules
set -eux -o pipefail

# Install udev rules for TurtleBot3
cp "$(ros2 pkg prefix turtlebot3_bringup)"/share/turtlebot3_bringup/script/99-turtlebot3-cdc.rules /etc/udev/rules.d/
udevadm control --reload-rules
udevadm trigger