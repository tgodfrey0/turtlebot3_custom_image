# robot-image.bb - Base robot image (no ROS)
#
# Builds a minimal robot image with user setup, networking,
# first-boot scripts, and common packages. No ROS2 support.

require robot-image.inc

SUMMARY = "Base robot image"
DESCRIPTION = "Minimal robot image without ROS2 support"
