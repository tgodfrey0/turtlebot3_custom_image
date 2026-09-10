# robot-image.inc - Base image configuration for all robot images

inherit core-image
inherit robot-image

# Common robot image features
IMAGE_FEATURES:append = " \
    package-management \
    "

IMAGE_INSTALL:append = " \
    packagegroup-core-ssh-openssh \
    openssh \
    openssh-sshd \
    openssh-sftp-server \
    tmux \
    robot-user \
    robot-config \
    robot-firstboot \
    robot-udev \
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
    wpa-supplicant \
    netplan \
    kbd \
    podman \
    "

# Minimal image size - always grow to fit contents exactly
IMAGE_ROOTFS_SIZE = "0"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Disable recommended images, we build our own
IMAGE_FEATURES:remove = "read-only-rootfs"

# -----------------------------------------------------------------------------
# User account - login works via ROBOT_USER + password (and empty root password)
# -----------------------------------------------------------------------------
# The account is created with the extrausers class at rootfs time, which is the
# supported way to provision users in images. Password is patched into
# /etc/shadow via do_rootfs_append to avoid shell expansion issues.

inherit extrausers

ROBOT_USER ??= "robot"
ROBOT_PASS ??= "changeme"

EXTRA_USERS_PARAMS = "\
    useradd -m -s /bin/bash -G sudo,dialout,tty,input ${ROBOT_USER}; \
"

# Patch the password hash directly into /etc/shadow after do_rootfs.
# The extrausers EXTRA_USERS_PARAMS pipeline mangles $ characters in hashes
# (e.g. $6 → empty positional param), so we bypass it entirely and write the
# hash with pure Python file I/O — no shell involved.
python do_rootfs:append() {
    import hashlib, os, subprocess, re

    user = d.getVar('ROBOT_USER') or 'robot'
    pw = d.getVar('ROBOT_PASS') or 'changeme'
    rootfs = d.getVar('IMAGE_ROOTFS')

    salt = hashlib.md5(('uav' + user + pw).encode()).hexdigest()[:16]
    out = subprocess.run(
        ['openssl', 'passwd', '-6', '-salt', salt, pw],
        capture_output=True, text=True)
    if out.returncode != 0:
        bb.fatal("Failed to hash ROBOT_PASS with openssl: %s" % out.stderr)

    shadow = os.path.join(rootfs, 'etc', 'shadow')
    with open(shadow) as f:
        content = f.read()
    content = re.sub(
        rf'^{user}:.*$',
        f'{user}:{out.stdout.strip()}:15069:0:99999:7:::',
        content, flags=re.MULTILINE)
    with open(shadow, 'w') as f:
        f.write(content)

    # Fix ip command: /usr/sbin/ip is a broken alternatives symlink.
    # Create a symlink in /usr/local/bin so it's in regular user PATH.
    ip_path = os.path.join(rootfs, 'usr', 'sbin', 'ip')
    local_bin = os.path.join(rootfs, 'usr', 'local', 'bin')
    os.makedirs(local_bin, exist_ok=True)
    ip_local = os.path.join(local_bin, 'ip')
    if not os.path.exists(ip_local):
        os.symlink('/usr/sbin/ip', ip_local)

    # UK keyboard layout for the local console and kbd defaults.
    with open(os.path.join(rootfs, 'etc', 'vconsole.conf'), 'w') as f:
        f.write('KEYMAP=uk\n')
    os.makedirs(os.path.join(rootfs, 'etc', 'default'), exist_ok=True)
    with open(os.path.join(rootfs, 'etc', 'default', 'keyboard'), 'w') as f:
        f.write('XKBMODEL="pc105"\n')
        f.write('XKBLAYOUT="gb"\n')
        f.write('XKBVARIANT=""\n')
        f.write('XKBOPTIONS=""\n')

    # /usr/sbin is not included in a regular user's default PATH.
    netplan_path = os.path.join(rootfs, 'usr', 'sbin', 'netplan')
    netplan_local = os.path.join(local_bin, 'netplan')
    if os.path.exists(netplan_path) and not os.path.exists(netplan_local):
        os.symlink('/usr/sbin/netplan', netplan_local)
}

# sudo is required for the NOPASSWD sudoers drop-in shipped by robot-user
IMAGE_INSTALL:append = " \
    sudo \
    "
