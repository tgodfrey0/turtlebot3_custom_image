# robot-image-ros.bb - Robot image with ROS2 support
#
# Extends the base robot image with ROS2 packages and TurtleBot3 support.
# Requires meta-ros layers to be present in bblayers.conf.

require robot-image.inc

SUMMARY = "Robot image with ROS2"
DESCRIPTION = "Robot image with ROS2 and TurtleBot3 support"

# ROS2 is required for this image
REQUIRED_DISTRO_FEATURES += "ros"

# ROS2 base packages
IMAGE_INSTALL:append = " \
    ros-core \
    ros-image-core \
    python3-colcon-common-extensions \
    "

# TurtleBot3 packages (conditional on ROBOT_TYPE)
IMAGE_INSTALL:append = " \
    ${@oe.utils.conditional('ROBOT_TYPE', 'turtlebot3', 'turtlebot3-packages turtlebot3-env turtlebot3-udev', '', d)} \
    "

# OpenCR support (conditional)
IMAGE_INSTALL:append = " \
    ${@oe.utils.conditional('OPENCR_SUPPORT', '1', 'opencr', '', d)} \
    "

# Camera support (conditional)
IMAGE_INSTALL:append = " \
    ${@oe.utils.conditional('CAMERA_SUPPORT', '1', 'camera-setup', '', d)} \
    "
