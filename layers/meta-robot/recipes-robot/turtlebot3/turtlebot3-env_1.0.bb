# turtlebot3-env_1.0.bb - TurtleBot3 environment variables
#
# Sets up ROS2 environment variables for TurtleBot3.
# Migrated from robots/turtlebot3/30_robot_env.sh.

SUMMARY = "TurtleBot3 environment"
DESCRIPTION = "Sets TurtleBot3 environment variables"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

ROS_DISTRO ??= "jazzy"
ROBOT_MODEL ??= "burger"
LDS_MODEL ??= "LDS-02"
ROS_DOMAIN_ID ??= "0"
ROBOT_USER ??= "robot"

do_install() {
    install -d -m 0755 ${D}${sysconfdir}/profile.d

    # Map waffle model to waffle_pi for TurtleBot3
    if [ "${ROBOT_MODEL}" = "waffle" ]; then
        TB3_MODEL="waffle_pi"
    else
        TB3_MODEL="${ROBOT_MODEL}"
    fi

    cat > ${D}${sysconfdir}/profile.d/90-turtlebot3-env.sh << EOF
export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}
export LDS_MODEL=${LDS_MODEL}
export TURTLEBOT3_MODEL=${TB3_MODEL}
export OPENCR_MODEL=${TB3_MODEL}
alias bringup="ros2 launch turtlebot3_bringup robot.launch.py"
EOF
}

FILES:${PN} = "${sysconfdir}/profile.d/90-turtlebot3-env.sh"
