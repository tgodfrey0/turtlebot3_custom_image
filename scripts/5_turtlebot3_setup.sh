#!/bin/bash

echo -e "\e[1;32mTurtleBot3 setup\e[0m"

apt install python3-argcomplete python3-colcon-common-extensions libboost-system-dev build-essential
apt install ros-humble-hls-lfcd-lds-driver
apt install ros-humble-turtlebot3-msgs
apt install ros-humble-dynamixel-sdk
apt install libudev-dev
mkdir -p /root/turtlebot3_ws/src && cd /root/turtlebot3_ws/src
git clone -b humble-devel https://github.com/ROBOTIS-GIT/turtlebot3.git
git clone -b ros2-devel https://github.com/ROBOTIS-GIT/ld08_driver.git
cd /root/turtlebot3_ws/src/turtlebot3
rm -r turtlebot3_cartographer turtlebot3_navigation2
cd /root/turtlebot3_ws/
echo 'source /opt/ros/humble/setup.bash' >> /etc/profile.d/90-turtlebot-ros-profile.sh
source /etc/profile.d/90-turtlebot-ros-profile.sh
colcon build --symlink-install --parallel-workers 1
echo 'source /root/turtlebot3_ws/install/setup.bash' >> /etc/profile.d/90-turtlebot-ros-profile.sh
source /etc/profile.d/90-turtlebot-ros-profile.sh

cp `ros2 pkg prefix turtlebot3_bringup`/share/turtlebot3_bringup/script/99-turtlebot3-cdc.rules /etc/udev/rules.d/
udevadm control --reload-rules
udevadm trigger

echo 'export ROS_DOMAIN_ID=89' >> /etc/profile.d/90-turtlebot-ros-profile.sh
echo 'export LDS_MODEL=LDS-02' >> /etc/profile.d/90-turtlebot-ros-profile.sh
echo 'export TURTLEBOT3_MODEL=waffle_pi' >> /etc/profile.d/90-turtlebot-ros-profile.sh
echo 'alias bringup="ros2 launch turtlebot3_bringup robot.launch.py"' >> /etc/profile.d/90-turtlebot-ros-profile.sh
source /etc/profile.d/90-turtlebot-ros-profile.sh
