#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mInstalling ROS ${ROS_DISTRO}\e[0m"

locale-gen en_GB en_GB.UTF-8
update-locale LC_ALL=en_GB.UTF-8 LANG=en_GB.UTF-8
export LANG=en_GB.UTF-8

add-apt-repository universe

curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null

apt-get -y update

# Downgrade libraries that security updates bumped past ROS's exact version pins
apt-get -y install --allow-downgrades \
  libzstd1=1.5.5+dfsg2-2build1 \
  libdrm2=2.4.120-2build1 \
  libunwind8=1.6.2-3build1

_ROS_PKGS="ros-${ROS_DISTRO}-ros-base ros-dev-tools ros-${ROS_DISTRO}-xacro ros-${ROS_DISTRO}-image-transport-plugins"
apt-get --simulate install ${_ROS_PKGS} > /dev/null 2>&1
apt-get -y install ${_ROS_PKGS}
unset _ROS_PKGS

echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /etc/profile.d/90-turtlebot-ros-profile.sh
chmod 755 /etc/profile.d/90-turtlebot-ros-profile.sh
