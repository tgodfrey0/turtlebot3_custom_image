#!/bin/bash
set -ex -o pipefail

read USERNAME < /etc/robot-user

set +u
source /etc/profile.d/90-ros-profile.sh 2>/dev/null || true
set -u

if [[ -f /home/${USERNAME}/.setup_opencr ]]; then
    export OPENCR_PORT=/dev/ttyACM0

    ROBOT_MODEL=""
    if [[ -f /etc/robot-config/robot_model ]]; then
        ROBOT_MODEL=$(cat /etc/robot-config/robot_model)
    fi

    cd /home/${USERNAME}/opencr_update
    ./update.sh $OPENCR_PORT ${ROBOT_MODEL:-burger}.opencr

    rm /home/${USERNAME}/.setup_opencr
fi
