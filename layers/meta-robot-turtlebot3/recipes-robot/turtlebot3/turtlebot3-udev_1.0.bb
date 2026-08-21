# turtlebot3-udev_1.0.bb - TurtleBot3 udev rules
#
# Installs udev rules for TurtleBot3 USB devices.
# Migrated from robots/turtlebot3/20_setup_udev.sh.

SUMMARY = "TurtleBot3 udev rules"
DESCRIPTION = "Installs udev rules for TurtleBot3 USB devices"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

ROS_DISTRO ??= "jazzy"

DEPENDS += "ros-${ROS_DISTRO}-turtlebot3-bringup"

do_install() {
    # Install udev rules from turtlebot3_bringup package
    install -d -m 0755 ${D}${sysconfdir}/udev/rules.d

    UDEV_RULES=$(ros2 pkg prefix turtlebot3_bringup)/share/turtlebot3_bringup/script/99-turtlebot3-cdc.rules
    if [ -f "$UDEV_RULES" ]; then
        install -m 0644 "$UDEV_RULES" ${D}${sysconfdir}/udev/rules.d/99-turtlebot3-cdc.rules
    else
        # Fallback: create a basic udev rule for TurtleBot3
        cat > ${D}${sysconfdir}/udev/rules.d/99-turtlebot3-cdc.rules << 'EOF'
# TurtleBot3 OpenCR udev rules
SUBSYSTEM=="tty", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="0042", MODE="0666", GROUP="dialout"
SUBSYSTEM=="tty", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="0042", SYMLINK+="ttyACM0"
EOF
    fi
}

FILES:${PN} = "${sysconfdir}/udev/rules.d/99-turtlebot3-cdc.rules"
