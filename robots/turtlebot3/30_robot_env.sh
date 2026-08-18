#!/bin/bash
# TurtleBot3 robot plugin - step 30: write environment variables & profile
set -eux -o pipefail

ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
LIDAR="${LIDAR:-LDS-02}"
ROBOT_MODEL="${ROBOT_MODEL:-burger}"

# TURTLEBOT3_MODEL uses "_pi" suffix for the Waffle Pi variant
if [ "$ROBOT_MODEL" = "waffle" ]; then
    TURTLEBOT3_MODEL="waffle_pi"
else
    TURTLEBOT3_MODEL="$ROBOT_MODEL"
fi
export TURTLEBOT3_MODEL

# Write TurtleBot3 environment variables
{
  echo "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"
  echo "export LDS_MODEL=$LIDAR"
  echo "export TURTLEBOT3_MODEL=$TURTLEBOT3_MODEL"
  echo "export OPENCR_MODEL=$TURTLEBOT3_MODEL"
  echo 'alias bringup="ros2 launch turtlebot3_bringup robot.launch.py"'
} | tee -a /etc/profile.d/90-ros-profile.sh > /dev/null