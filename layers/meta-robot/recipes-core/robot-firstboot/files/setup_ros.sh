#!/bin/bash
set -eux -o pipefail

read USERNAME < /etc/robot-user

WORKSPACE="/home/${USERNAME}/colcon_ws"
if [[ -f /etc/robot-config/workspace_path ]]; then
    WORKSPACE=$(cat /etc/robot-config/workspace_path)
fi

if [[ -f /home/${USERNAME}/.setup_ros ]]; then
    cd "$WORKSPACE"
    colcon build
    set +u
    source install/setup.bash
    set -u

    rm /home/${USERNAME}/.setup_ros
fi
