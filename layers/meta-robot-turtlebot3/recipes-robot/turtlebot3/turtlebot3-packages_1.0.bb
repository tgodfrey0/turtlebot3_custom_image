# turtlebot3-packages_1.0.bb - TurtleBot3 ROS packages
#
# Installs TurtleBot3-specific ROS2 packages and clones required repositories.
# Migrated from robots/turtlebot3/00_install_packages.sh.

SUMMARY = "TurtleBot3 ROS packages"
DESCRIPTION = "Installs TurtleBot3 ROS2 packages and dependencies"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# ROS2 distro and robot model
ROS_DISTRO ??= "jazzy"
ROBOT_MODEL ??= "burger"
LDS_MODEL ??= "LDS-02"
ROBOT_USER ??= "robot"

# Dependencies
DEPENDS += " \
    ros-${ROS_DISTRO}-ros-base \
    ros-dev-tools \
    python3-colcon-common-extensions \
    python3-argcomplete \
    libboost-system-dev \
    build-essential \
    libudev-dev \
"

# TurtleBot3-specific ROS packages
RDEPENDS:${PN} += " \
    ros-${ROS_DISTRO}-hls-lfcd-lds-driver \
    ros-${ROS_DISTRO}-turtlebot3-msgs \
    ros-${ROS_DISTRO}-dynamixel-sdk \
    ros-${ROS_DISTRO}-xacro \
    ros-${ROS_DISTRO}-image-transport-plugins \
"

# Source repositories to clone
SRC_URI = " \
    git://github.com/ROBOTIS-GIT/turtlebot3.git;branch=${ROS_DISTRO};name=turtlebot3;destsuffix=turtlebot3 \
    git://github.com/ROBOTIS-GIT/ld08_driver.git;branch=${ROS_DISTRO};name=ld08;destsuffix=ld08_driver \
    git://github.com/ROBOTIS-GIT/coin_d4_driver.git;name=coin_d4;destsuffix=coin_d4_driver \
"

SRCREV_turtlebot3 = "${AUTOREV}"
SRCREV_ld08 = "${AUTOREV}"
SRCREV_coin_d4 = "${AUTOREV}"

S = "${WORKDIR}"

do_compile() {
    # Create colcon workspace
    install -d -m 0755 ${D}/home/${ROBOT_USER}/colcon_ws/src

    # Copy cloned repos into workspace
    cp -r ${WORKDIR}/turtlebot3 ${D}/home/${ROBOT_USER}/colcon_ws/src/
    cp -r ${WORKDIR}/ld08_driver ${D}/home/${ROBOT_USER}/colcon_ws/src/
    cp -r ${WORKDIR}/coin_d4_driver ${D}/home/${ROBOT_USER}/colcon_ws/src/

    # Remove navigation/cartographer (not needed for basic bringup)
    rm -rf ${D}/home/${ROBOT_USER}/colcon_ws/src/turtlebot3/turtlebot3_cartographer
    rm -rf ${D}/home/${ROBOT_USER}/colcon_ws/src/turtlebot3/turtlebot3_navigation2

    # Build the workspace
    cd ${D}/home/${ROBOT_USER}/colcon_ws
    . /opt/ros/${ROS_DISTRO}/setup.sh
    colcon build --symlink-install --parallel-workers 1

    # Write ROS profile
    install -d ${D}${sysconfdir}/profile.d
    cat > ${D}${sysconfdir}/profile.d/90-ros-profile.sh << EOF
. /opt/ros/${ROS_DISTRO}/setup.sh
. /home/${ROBOT_USER}/colcon_ws/install/setup.sh
export ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}
export LDS_MODEL=${LDS_MODEL}
export TURTLEBOT3_MODEL=${ROBOT_MODEL}
export OPENCR_MODEL=${ROBOT_MODEL}
alias bringup="ros2 launch turtlebot3_bringup robot.launch.py"
EOF

    chown -R ${ROBOT_USER}:${ROBOT_USER} ${D}/home/${ROBOT_USER}/colcon_ws
}

FILES:${PN} = " \
    /home/${ROBOT_USER}/colcon_ws/* \
    ${sysconfdir}/profile.d/90-ros-profile.sh \
"

# Inherit ros insane setup if available
inherit ros_insane_dev_so
