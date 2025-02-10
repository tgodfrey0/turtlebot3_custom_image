#!/bin/bash
set -eux -o pipefail

# Delete the default Ubuntu user
userdel -r ubuntu

# Create a new user with the username 'robot'
useradd \
    --create-home \
    --shell /bin/bash \
    --groups sudo,adm,dialout,video,gpio,ftp,ssh \
    robot

# Set password for the new user
echo "robot:turtlebot3" | chpasswd

# Grant full sudo privileges without requiring a password
echo "robot ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/robot
chmod 0440 /etc/sudoers.d/robot

# Ensure ROS-related permissions (e.g., access to serial ports)
usermod -aG dialout robot

# Configure SSH access
grep -q "^AllowGroups" /etc/ssh/sshd_config || echo "AllowGroups ssh" >> /etc/ssh/sshd_config
usermod -aG ssh robot
systemctl restart sshd

# Configure FTP access
usermod -aG ftp robot

# ROS_WORKSPACE="/opt/ros"
# if [ -d "$ROS_WORKSPACE" ]; then
#     chown -R robot:robot "$ROS_WORKSPACE"
#     chmod -R 755 "$ROS_WORKSPACE"
# fi

echo "User 'robot' created with full admin privileges and permissions for ROS, SSH, and FTP."
