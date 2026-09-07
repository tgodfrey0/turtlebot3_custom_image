# common-packages_1.0.bb - Common packages for all robot images
#
# Installs packages common to all robots: git, curl, editors, networking tools.
# Replaces the old scripts/10_packages.sh Packer provisioner.

SUMMARY = "Common robot packages"
DESCRIPTION = "Installs packages common to all robot images"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

RDEPENDS:${PN} = " \
    git \
    curl \
    wget \
    nano \
    htop \
    tmux \
    openssh-sftp-server \
    python3-pip \
    python3-venv \
    can-utils \
    i2c-tools \
    iputils-ping \
    net-tools \
    iproute2 \
    util-linux \
    procps \
    ffmpeg \
    libgpiod-tools \
    "

# Rust toolchain (installed via rustup, not OE recipes)
# This is a placeholder - actual Rust install happens at first boot or build time
RUST_INSTALL ??= "0"
