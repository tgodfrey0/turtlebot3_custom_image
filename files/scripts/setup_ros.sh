#!/bin/bash
set -eux -o pipefail

USERNAME="${USERNAME}"

if [[ -f /home/${USERNAME}/.setup_ros ]]; then
  cd /home/${USERNAME}/turtlebot3_ws/
  colcon build
  set +u
  source install/setup.bash
  set -u

  rm /home/${USERNAME}/.setup_ros
fi
