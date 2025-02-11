#!/bin/bash
set -eux -o pipefail

if [[ -f /home/robot/.setup_ros ]]; then
  cd /home/robot/turtlebot3_ws/src/turtlebot3_mrs_launcher/
  ./setup.sh
  cd /home/robot/turtlebot3_ws/
  colcon build
  source install/setup.bash

  rm /home/robot/.setup_ros
fi
