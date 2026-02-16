#!/bin/bash
set -ex -o pipefail

# Use environment variables with defaults
USERNAME="${USERNAME:-robot}"
LIDAR="${LIDAR:-LDS-02}"

echo -e "\e[1;32mTurtleBot3 setup\e[0m"

apt-get -y install python3-argcomplete python3-colcon-common-extensions libboost-system-dev build-essential ros-humble-hls-lfcd-lds-driver ros-humble-turtlebot3-msgs ros-humble-dynamixel-sdk libudev-dev
mkdir -p "/home/$USERNAME/turtlebot3_ws/src" && cd "/home/$USERNAME/turtlebot3_ws/src"
git clone -b humble https://github.com/ROBOTIS-GIT/turtlebot3.git
git clone -b humble https://github.com/ROBOTIS-GIT/ld08_driver.git
git clone -b humble https://github.com/ROBOTIS-GIT/coin_d4_driver
cd "/home/$USERNAME/turtlebot3_ws/src/turtlebot3"
rm -r turtlebot3_cartographer turtlebot3_navigation2
cd "/home/$USERNAME/turtlebot3_ws/"
echo 'source /opt/ros/humble/setup.bash' | tee -a /etc/profile.d/90-turtlebot-ros-profile.sh > /dev/null
set +u
source /etc/profile.d/90-turtlebot-ros-profile.sh
set -u
colcon build --symlink-install --parallel-workers 1
echo "source /home/$USERNAME/turtlebot3_ws/install/setup.bash" | tee -a /etc/profile.d/90-turtlebot-ros-profile.sh > /dev/null
set +u
source /etc/profile.d/90-turtlebot-ros-profile.sh
set -u

cp "$(ros2 pkg prefix turtlebot3_bringup)"/share/turtlebot3_bringup/script/99-turtlebot3-cdc.rules /etc/udev/rules.d/
udevadm control --reload-rules
udevadm trigger

{
echo '# export ROS_DOMAIN_ID=0'
echo "export LDS_MODEL=$LIDAR"
echo "export TURTLEBOT3_MODEL=$TURTLEBOT3_MODEL"
echo "export OPENCR_MODEL=$OPENCR_MODEL"
echo 'alias bringup="ros2 launch turtlebot3_bringup robot.launch.py"'
} | tee -a /etc/profile.d/90-turtlebot-ros-profile.sh > /dev/null

set +u
source /etc/profile.d/90-turtlebot-ros-profile.sh
set -u

chmod 755 "/home/$USERNAME/turtlebot3_ws/install"/*
