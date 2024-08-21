#!/bin/bash
set -eux -o pipefail

if [[ -f /root/.setup_ros ]]; then
  cd /root/turtlebot3_ws/src/turtlebot3_mrs_launcher/
  ./setup.sh
  cd /root/turtlebot3_ws/
  colcon build
  source install/setup.bash

  rm /root/.setup_ros
fi
