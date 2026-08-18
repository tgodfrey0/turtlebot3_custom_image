#!/bin/bash
set -eux -o pipefail

ROBOT_TYPE="${ROBOT_TYPE:-generic}"
USERNAME="${USERNAME:-robot}"

echo -e "\e[1;32mRobot setup: ${ROBOT_TYPE}\e[0m"

# Check for robot plugin setup script
PLUGIN_DIR="/tmp/robot_plugin"
PLUGIN_SETUP="${PLUGIN_DIR}/setup.sh"

if [ -d "$PLUGIN_DIR" ] && [ -f "$PLUGIN_SETUP" ]; then
    echo "Running robot-specific setup for '${ROBOT_TYPE}'..."
    chmod +x "$PLUGIN_SETUP"
    source "$PLUGIN_SETUP"
else
    echo "No robot-specific setup found for '${ROBOT_TYPE}'. Skipping."
fi

# Write bringup command to config if provided
if [ -n "${BRINGUP_COMMAND:-}" ]; then
    echo "$BRINGUP_COMMAND" > /etc/robot-config/bringup_command
fi

# Write ROS workspace path if ROS is enabled
if [ "${ROS_ENABLED:-true}" = "true" ]; then
    echo "/home/${USERNAME}/colcon_ws" > /etc/robot-config/workspace_path
fi

# Clean up plugin files
rm -rf "$PLUGIN_DIR"
