# robot-firstboot_1.0.bb - First-boot setup scripts and services
#
# Installs all first-boot scripts and systemd oneshot services.
# Migrated from files/scripts/ and files/services/ in the Packer build.

SUMMARY = "Robot first-boot setup"
DESCRIPTION = "Installs first-boot scripts and systemd services"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://setup_hostname.sh \
    file://setup_network.sh \
    file://setup_firewall.sh \
    file://setup_ros.sh \
    file://setup_camera.sh \
    file://setup_tailscale.sh \
    file://setup_opencr.sh \
    file://bringup.sh \
    file://get_hostname.py \
    file://gen_netplan.py \
    file://fix-permissions.sh \
    file://fix-permissions.service \
    file://hostname_setup.service \
    file://network_setup.service \
    file://firewall_setup.service \
    file://tailscale_setup.service \
    file://camera_setup.service \
    file://ros_setup.service \
    file://opencr_setup.service \
    file://bringup.service \
"

ROBOT_USER ??= "robot"

# All scripts are POSIX shell - no dependencies needed
RDEPENDS:${PN} = " \
    bash \
    coreutils \
    python3 \
    python3-core \
    ufw \
"

do_install() {
    # Install first-boot scripts
    install -d -m 0755 ${D}/home/${ROBOT_USER}/setup_scripts

    install -m 0755 ${WORKDIR}/setup_hostname.sh ${D}/home/${ROBOT_USER}/setup_scripts/
    install -m 0755 ${WORKDIR}/setup_network.sh ${D}/home/${ROBOT_USER}/setup_scripts/
    install -m 0755 ${WORKDIR}/setup_firewall.sh ${D}/home/${ROBOT_USER}/setup_scripts/
    install -m 0755 ${WORKDIR}/setup_ros.sh ${D}/home/${ROBOT_USER}/setup_scripts/
    install -m 0755 ${WORKDIR}/setup_camera.sh ${D}/home/${ROBOT_USER}/setup_scripts/
    install -m 0755 ${WORKDIR}/setup_tailscale.sh ${D}/home/${ROBOT_USER}/setup_scripts/
    install -m 0755 ${WORKDIR}/setup_opencr.sh ${D}/home/${ROBOT_USER}/setup_scripts/
    install -m 0755 ${WORKDIR}/bringup.sh ${D}/home/${ROBOT_USER}/setup_scripts/

    # Install Python helper scripts
    install -m 0755 ${WORKDIR}/get_hostname.py ${D}/home/${ROBOT_USER}/setup_scripts/
    install -m 0755 ${WORKDIR}/gen_netplan.py ${D}/home/${ROBOT_USER}/setup_scripts/

    # Install fix-permissions script (runs once at boot to chown files to robot user)
    install -d -m 0755 ${D}${bindir}
    install -m 0755 ${WORKDIR}/fix-permissions.sh ${D}${bindir}/fix-permissions.sh

    # Install systemd service files
    install -d -m 0755 ${D}${sysconfdir}/systemd/system

    install -m 0644 ${WORKDIR}/hostname_setup.service ${D}${sysconfdir}/systemd/system/
    install -m 0644 ${WORKDIR}/network_setup.service ${D}${sysconfdir}/systemd/system/
    install -m 0644 ${WORKDIR}/firewall_setup.service ${D}${sysconfdir}/systemd/system/
    install -m 0644 ${WORKDIR}/tailscale_setup.service ${D}${sysconfdir}/systemd/system/
    install -m 0644 ${WORKDIR}/camera_setup.service ${D}${sysconfdir}/systemd/system/
    install -m 0644 ${WORKDIR}/ros_setup.service ${D}${sysconfdir}/systemd/system/
    install -m 0644 ${WORKDIR}/opencr_setup.service ${D}${sysconfdir}/systemd/system/
    install -m 0644 ${WORKDIR}/bringup.service ${D}${sysconfdir}/systemd/system/
    install -m 0644 ${WORKDIR}/fix-permissions.service ${D}${sysconfdir}/systemd/system/

    # Enable oneshot services
    install -d -m 0755 ${D}${sysconfdir}/systemd/system/multi-user.target.wants

    ln -sf ${sysconfdir}/systemd/system/fix-permissions.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/fix-permissions.service
    ln -sf ${sysconfdir}/systemd/system/hostname_setup.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/hostname_setup.service
    ln -sf ${sysconfdir}/systemd/system/firewall_setup.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/firewall_setup.service
    ln -sf ${sysconfdir}/systemd/system/tailscale_setup.service \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/tailscale_setup.service
}

FILES:${PN} = " \
    /home/${ROBOT_USER}/setup_scripts/* \
    ${bindir}/fix-permissions.sh \
    ${sysconfdir}/systemd/system/*.service \
    ${sysconfdir}/systemd/system/multi-user.target.wants/*.service \
"
