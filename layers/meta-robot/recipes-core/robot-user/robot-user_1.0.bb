# robot-user_1.0.bb - User setup recipe
#
# Ships the sudoers drop-in, SSH key material, and config marker files for
# the ROBOT_USER account. The account itself is created by the extrausers
# class in robot-image.inc (the supported way to provision image users).

SUMMARY = "Robot user setup"
DESCRIPTION = "Sudo and SSH configuration for the robot user account"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = ""

ROBOT_USER ??= "robot"
ROBOT_SSH_KEY ??= ""
HOSTNAME_PREFIX ??= "robot"

do_install() {
    install -d ${D}${sysconfdir}/robot-config
    install -d ${D}${sysconfdir}/sudoers.d

    echo "${ROBOT_USER}" > ${D}${sysconfdir}/robot-user
    echo "${HOSTNAME_PREFIX}" > ${D}${sysconfdir}/robot-config/hostname_prefix

    echo "${ROBOT_USER} ALL=(ALL) NOPASSWD:ALL" > ${D}${sysconfdir}/sudoers.d/${ROBOT_USER}
    chmod 0440 ${D}${sysconfdir}/sudoers.d/${ROBOT_USER}

    # SSH directory. Owned by root but readable - sshd StrictModes accepts
    # this and the user gets created at rootfs time with a matching name.
    if [ -n "${ROBOT_SSH_KEY}" ]; then
        install -d -m 0755 ${D}/home/${ROBOT_USER}/.ssh
        echo "${ROBOT_SSH_KEY}" > ${D}/home/${ROBOT_USER}/.ssh/authorized_keys
        chmod 0644 ${D}/home/${ROBOT_USER}/.ssh/authorized_keys
    fi
}

FILES:${PN} = " \
    ${sysconfdir}/robot-user \
    ${sysconfdir}/robot-config/hostname_prefix \
    ${sysconfdir}/sudoers.d/${ROBOT_USER} \
    /home/${ROBOT_USER}/.ssh/authorized_keys \
"

CONFFILES:${PN} = " \
    ${sysconfdir}/robot-user \
    ${sysconfdir}/robot-config/hostname_prefix \
"

# The extrausers-created user must exist before firstboot scripts that
# reference /home/${ROBOT_USER} are usable; ordering is handled at rootfs.
RDEPENDS:${PN} = "sudo"
