#!/bin/bash
# fix-permissions.sh - Set ownership of robot user files at first boot
#
# The robot user is created by extrausers at rootfs time, but files
# installed by robot-config and robot-firstboot are root-owned.
# This service runs once at boot to fix ownership before firstboot scripts.

ROBOT_USER=$(cat /etc/robot-user)

chown -R ${ROBOT_USER}:${ROBOT_USER} /home/${ROBOT_USER}/setup_scripts
chown -R ${ROBOT_USER}:${ROBOT_USER} /home/${ROBOT_USER}/.config
chown -R ${ROBOT_USER}:${ROBOT_USER} /home/${ROBOT_USER}/.setup_*
