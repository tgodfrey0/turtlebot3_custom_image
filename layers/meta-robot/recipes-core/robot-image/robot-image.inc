# robot-image.inc - Base image configuration for all robot images

inherit core-image

# Common robot image features
IMAGE_FEATURES:remove = "debug-tweaks"

IMAGE_INSTALL:append = " \
    packagegroup-core-ssh-openssh \
    packagegroup-base-sshd \
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
    spi-tools \
    python3 \
    python3-pip \
    python3-venv \
    "

# Minimal image size - always grow to fit contents exactly
IMAGE_ROOTFS_SIZE = "0"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Disable recommended images, we build our own
IMAGE_FEATURES:remove = "read-only-rootfs"
