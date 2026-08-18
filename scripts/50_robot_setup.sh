#!/bin/bash
set -eux -o pipefail

ROBOT_TYPE="${ROBOT_TYPE:-generic}"
USERNAME="${USERNAME:-robot}"

echo -e "\e[1;32mRobot setup: ${ROBOT_TYPE}\e[0m"

# Check for robot plugin setup scripts
PLUGIN_DIR="/tmp/robot_plugin"

# Run plugin scripts in sorted order. Prefix names with a number to define
# ordering (e.g. 00_install_packages.sh, 10_build_workspace.sh, ...).
# Only numeric-prefixed scripts run here; other scripts (e.g. runtime
# first-boot helpers) are copied into setup_scripts by the plugin itself.
PLUGIN_SCRIPTS=$(find "$PLUGIN_DIR" -maxdepth 1 -name '[0-9]*.sh' 2>/dev/null | sort)

if [ -n "$PLUGIN_SCRIPTS" ]; then
    echo "Running robot-specific setup for '${ROBOT_TYPE}'..."
    while IFS= read -r script; do
        echo -e "\e[1;32m  -> $(basename "$script")\e[0m"
        chmod +x "$script"
        source "$script"
    done <<< "$PLUGIN_SCRIPTS"
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
