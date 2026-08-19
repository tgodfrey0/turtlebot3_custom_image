# robot-user_1.0.bb - User setup recipe
#
# Creates the robot user with sudo, SSH key, and serial group access.
# Replaces the old scripts/00_setup_user.sh Packer provisioner.

SUMMARY = "Robot user setup"
DESCRIPTION = "Creates the robot user account with sudo and SSH access"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = ""

# Robot configuration variables
ROBOT_USER ??= "robot"
ROBOT_PASS ??= "changeme"
ROBOT_SSH_KEY ??= ""
HOSTNAME_PREFIX ??= "robot"

# Use Python for password hashing
inherit python3native

python do_compile() {
    import crypt
    import os
    import random
    import string

    password = d.getVar('ROBOT_PASS')
    salt_chars = string.ascii_letters + string.digits + './'
    salt = '$6$' + ''.join(random.choices(salt_chars, k=16)) + '$'
    hashed = crypt.crypt(password, salt)

    with open(os.path.join(d.getVar('WORKDIR'), 'shadow_hash'), 'w') as f:
        f.write(hashed)
}

do_install() {
    SHADOW_HASH=$(cat ${WORKDIR}/shadow_hash)

    groupadd -f ${ROBOT_USER}

    useradd -m -g ${ROBOT_USER} -s /bin/bash \
        -p "${SHADOW_HASH}" \
        ${ROBOT_USER} || true

    usermod -aG sudo ${ROBOT_USER} || true

    echo "${ROBOT_USER} ALL=(ALL) NOPASSWD:ALL" > ${D}${sysconfdir}/sudoers.d/${ROBOT_USER}
    chmod 0440 ${D}${sysconfdir}/sudoers.d/${ROBOT_USER}

    usermod -aG dialout ${ROBOT_USER} || true
    usermod -aG input ${ROBOT_USER} || true

    install -d -m 0700 /home/${ROBOT_USER}/.ssh

    if [ -n "${ROBOT_SSH_KEY}" ]; then
        echo "${ROBOT_SSH_KEY}" > /home/${ROBOT_USER}/.ssh/authorized_keys
        chmod 0600 /home/${ROBOT_USER}/.ssh/authorized_keys
    fi

    chown -R ${ROBOT_USER}:${ROBOT_USER} /home/${ROBOT_USER}/.ssh

    echo "${ROBOT_USER}" > ${D}${sysconfdir}/robot-user

    install -d -m 0755 ${D}${sysconfdir}/robot-config
    echo "${HOSTNAME_PREFIX}" > ${D}${sysconfdir}/robot-config/hostname_prefix
}

FILES:${PN} = " \
    ${sysconfdir}/robot-user \
    ${sysconfdir}/robot-config/hostname_prefix \
    ${sysconfdir}/sudoers.d/${ROBOT_USER} \
"

CONFFILES:${PN} = " \
    ${sysconfdir}/robot-user \
    ${sysconfdir}/robot-config/hostname_prefix \
"
