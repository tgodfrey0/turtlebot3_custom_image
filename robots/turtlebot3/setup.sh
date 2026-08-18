#!/bin/bash
# TurtleBot3 robot plugin - build-time setup
# This script is sourced by scripts/50_robot_setup.sh during image build.
set -eux -o pipefail

echo -e "\e[1;32mTurtleBot3 setup\e[0m"

USERNAME="${USERNAME:-robot}"
LIDAR="${LIDAR:-LDS-02}"
ROS_DISTRO="${ROS_DISTRO:-humble}"
ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
ROBOT_MODEL="${ROBOT_MODEL:-burger}"

# TURTLEBOT3_MODEL uses "_pi" suffix for the Waffle Pi variant
if [ "$ROBOT_MODEL" = "waffle" ]; then
    TURTLEBOT3_MODEL="waffle_pi"
else
    TURTLEBOT3_MODEL="$ROBOT_MODEL"
fi
export TURTLEBOT3_MODEL

# Write model config for runtime scripts
echo "$ROBOT_MODEL" > /etc/robot-config/robot_model

# Install TurtleBot3 ROS packages
_TB3_PKGS="python3-argcomplete python3-colcon-common-extensions libboost-system-dev build-essential ros-${ROS_DISTRO}-hls-lfcd-lds-driver ros-${ROS_DISTRO}-turtlebot3-msgs ros-${ROS_DISTRO}-dynamixel-sdk libudev-dev"
apt-get --simulate install ${_TB3_PKGS} > /dev/null 2>&1
apt-get -y install ${_TB3_PKGS}
unset _TB3_PKGS

# Clone TurtleBot3 and related repos
mkdir -p "/home/$USERNAME/colcon_ws/src" && cd "/home/$USERNAME/colcon_ws/src"
git clone -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/turtlebot3.git
git clone -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/ld08_driver.git
git clone -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/coin_d4_driver

# Remove navigation/cartographer (not needed for basic bringup)
cd "/home/$USERNAME/colcon_ws/src/turtlebot3"
rm -r turtlebot3_cartographer turtlebot3_navigation2

# Source ROS and build workspace
cd "/home/$USERNAME/colcon_ws/"
echo "source /opt/ros/${ROS_DISTRO}/setup.bash" | tee -a /etc/profile.d/90-ros-profile.sh > /dev/null
set +u
source /etc/profile.d/90-ros-profile.sh
set -u
colcon build --symlink-install --parallel-workers 1
echo "source /home/$USERNAME/colcon_ws/install/setup.bash" | tee -a /etc/profile.d/90-ros-profile.sh > /dev/null
set +u
source /etc/profile.d/90-ros-profile.sh
set -u

# Install udev rules for TurtleBot3
cp "$(ros2 pkg prefix turtlebot3_bringup)"/share/turtlebot3_bringup/script/99-turtlebot3-cdc.rules /etc/udev/rules.d/
udevadm control --reload-rules
udevadm trigger

# Write TurtleBot3 environment variables
{
  echo "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"
  echo "export LDS_MODEL=$LIDAR"
  echo "export TURTLEBOT3_MODEL=$TURTLEBOT3_MODEL"
  echo "export OPENCR_MODEL=$TURTLEBOT3_MODEL"
  echo 'alias bringup="ros2 launch turtlebot3_bringup robot.launch.py"'
} | tee -a /etc/profile.d/90-ros-profile.sh > /dev/null

set +u
source /etc/profile.d/90-ros-profile.sh
set -u

chmod 755 "/home/$USERNAME/colcon_ws/install"/*

# Copy robot-specific runtime scripts into place
mkdir -p /home/$USERNAME/setup_scripts
cp /tmp/robot_plugin/setup_opencr.sh /home/$USERNAME/setup_scripts/setup_opencr.sh
chmod +x /home/$USERNAME/setup_scripts/setup_opencr.sh

# --- OpenCR setup ---
echo -e "\e[1;32mOpenCR setup\e[0m"

dpkg --add-architecture armhf
apt-get -y update
apt-get -y install libc6:armhf

export OPENCR_PORT=/dev/ttyACM0
rm -rf ./opencr_update.tar.bz2

cd /home/$USERNAME/
wget https://github.com/ROBOTIS-GIT/OpenCR-Binaries/raw/master/turtlebot3/ROS2/latest/opencr_update.tar.bz2
tar -xvf ./opencr_update.tar.bz2

touch /home/$USERNAME/.setup_opencr
chmod +x /home/$USERNAME/setup_scripts/setup_opencr.sh
systemctl enable opencr_setup.service

# Set up bringup service (not auto-enabled, user must enable manually)
chmod +x /home/$USERNAME/setup_scripts/bringup.sh
