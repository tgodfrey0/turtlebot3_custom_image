# opencr_1.0.bb - OpenCR motor controller firmware
#
# Downloads OpenCR firmware and sets up first-boot flash.
# Migrated from robots/turtlebot3/40_setup_opencr.sh.

SUMMARY = "OpenCR firmware setup"
DESCRIPTION = "Downloads OpenCR firmware and configures first-boot flash"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

ROBOT_MODEL ??= "burger"
ROBOT_USER ??= "robot"

# OpenCR firmware download
SRC_URI = " \
    https://github.com/ROBOTIS-GIT/OpenCR-Binaries/raw/master/turtlebot3/ROS2/latest/opencr_update.tar.bz2 \
"

SRC_URI[sha256sum] = ""

# armhf support for OpenCR binary
PACKAGECONFIG:append = " armhf"
RDEPENDS:${PN} += " \
    libc6-armhf \
    gcc-armhf \
"

do_install() {
    # Create OpenCR update directory
    install -d -m 0755 ${D}/home/${ROBOT_USER}/opencr_update

    # Extract firmware
    cd ${D}/home/${ROBOT_USER}/opencr_update
    tar xjf ${WORKDIR}/opencr_update.tar.bz2

    # Copy first-boot flash script
    install -d -m 0755 ${D}/home/${ROBOT_USER}/setup_scripts
    install -m 0755 ${WORKDIR}/setup_opencr.sh ${D}/home/${ROBOT_USER}/setup_scripts/

    # Create first-boot marker
    touch ${D}/home/${ROBOT_USER}/.setup_opencr

    chown -R ${ROBOT_USER}:${ROBOT_USER} ${D}/home/${ROBOT_USER}/opencr_update
    chown -R ${ROBOT_USER}:${ROBOT_USER} ${D}/home/${ROBOT_USER}/setup_scripts
    chown ${ROBOT_USER}:${ROBOT_USER} ${D}/home/${ROBOT_USER}/.setup_opencr

    # Enable OpenCR setup service
    install -d -m 0755 ${D}${sysconfdir}/systemd/system/multi-user.target.wants
    # Note: service file is installed by robot-firstboot recipe
}

FILES:${PN} = " \
    /home/${ROBOT_USER}/opencr_update/* \
    /home/${ROBOT_USER}/setup_scripts/setup_opencr.sh \
    /home/${ROBOT_USER}/.setup_opencr \
"
