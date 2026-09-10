# robot-udev_1.0.bb - Serial port udev rules
#
# Installs udev rules for /dev/ttyAMA0 so the port is owned by the dialout
# group with mode 0660, allowing robot users to open it without root.

SUMMARY = "Serial port udev rules"
DESCRIPTION = "Sets permissions on /dev/ttyAMA0 for the dialout group"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = "file://99-ttyAMA.rules"

do_install() {
    install -d ${D}${sysconfdir}/udev/rules.d/
    install -m 0644 ${WORKDIR}/99-ttyAMA.rules ${D}${sysconfdir}/udev/rules.d/
}

FILES:${PN} = "${sysconfdir}/udev/rules.d/99-ttyAMA.rules"
