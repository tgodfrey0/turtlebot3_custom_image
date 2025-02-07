#!/bin/bash
set -eux -o pipefail

user="pi"
password="$(openssl passwd -salt robot robot)"

userdel -r pi

# Create robot user
useradd \
    --create-home \
    -s /bin/bash \
    -u 1000 \
    -G sudo,video,dialout,adm,gpio \
    -p "$password" \
    $user

mv /etc/sudoers.d/010_pi-nopasswd /etc/sudoers.d/010_robot-nopasswd
sed -i 's/pi/robot/g' /etc/sudoers.d/010_robot-nopasswd

echo "$user:$password" > /boot/userconf

# Enable ssh
touch /boot/ssh
