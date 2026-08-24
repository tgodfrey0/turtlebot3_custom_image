# robot-image.inc - Base image configuration for all robot images

inherit core-image

# Common robot image features
IMAGE_FEATURES:remove = "debug-tweaks"

IMAGE_FEATURES:append = " \
    package-management \
    "

IMAGE_INSTALL:append = " \
    packagegroup-core-ssh-openssh \
    robot-user \
    robot-config \
    robot-firstboot \
    common-packages \
    tailscale \
    packagegroup-core-full-cmdline \
    "

# Extra packages for robot images
IMAGE_INSTALL:append = " \
    i2c-tools \
    can-utils \
    python3 \
    python3-pip \
    python3-venv \
    "

# Minimal image size - always grow to fit contents exactly
IMAGE_ROOTFS_SIZE = "0"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Disable recommended images, we build our own
IMAGE_FEATURES:remove = "read-only-rootfs"

# -----------------------------------------------------------------------------
# User account (no debug-tweaks - login works via ROBOT_USER + password)
# -----------------------------------------------------------------------------
# The account is created with the extrausers class at rootfs time, which is the
# supported way to provision users in images.
#
# ROBOT_PASS_HASH takes a crypt(3) hash (e.g. `openssl passwd -6 'secret'`).
# If unset, one is derived from ROBOT_PASS below at parse time.

inherit extrausers

ROBOT_USER ??= "robot"
ROBOT_PASS ??= "changeme"
ROBOT_PASS_HASH ??= ""

python () {
    import hashlib
    import subprocess
    if not d.getVar('ROBOT_PASS_HASH'):
        user = d.getVar('ROBOT_USER') or 'robot'
        pw = d.getVar('ROBOT_PASS') or 'changeme'
        # Deterministic 16-char salt so re-parsing doesn't invalidate sstate
        salt = hashlib.md5(('uav' + user + pw).encode()).hexdigest()[:16]
        out = subprocess.run(
            ['openssl', 'passwd', '-6', '-salt', salt, pw],
            capture_output=True, text=True)
        if out.returncode != 0:
            bb.fatal("Failed to hash ROBOT_PASS with openssl: %s" % out.stderr)
        d.setVar('ROBOT_PASS_HASH', out.stdout.strip())
}

EXTRA_USERS_PARAMS = "\
    useradd -m -s /bin/bash -G sudo,dialout,input -p '${ROBOT_PASS_HASH}' ${ROBOT_USER}; \
"

# sudo is required for the NOPASSWD sudoers drop-in shipped by robot-user
IMAGE_INSTALL:append = " \
    sudo \
    "
