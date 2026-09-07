#!/bin/bash
set -eux -o pipefail

if [[ ! -f /etc/robot-config/bringup_command ]]; then
    echo "No bringup command configured. Skipping."
    exit 0
fi

BRINGUP_COMMAND=$(cat /etc/robot-config/bringup_command)

if [[ -z "$BRINGUP_COMMAND" ]]; then
    echo "Bringup command is empty. Skipping."
    exit 0
fi

set +u
if [[ -f /etc/profile.d/90-ros-profile.sh ]]; then
    source /etc/profile.d/90-ros-profile.sh
elif [[ -f /etc/profile.d/90-turtlebot-ros-profile.sh ]]; then
    source /etc/profile.d/90-turtlebot-ros-profile.sh
fi
set -u

echo "Running bringup: $BRINGUP_COMMAND"
$BRINGUP_COMMAND
