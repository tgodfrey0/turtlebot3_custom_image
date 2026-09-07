# robot-image.bbclass - Common image class for robot images
#
# Provides user setup, first-boot services, common packages,
# and Tailscale connectivity for all robot builds.

# Robot configuration variables (set via local.conf or toml2conf)
ROBOT_USER ??= "robot"
ROBOT_PASS ??= "changeme"
ROBOT_TYPE ??= "generic"
ROBOT_MODEL ??= ""
HOSTNAME_PREFIX ??= "robot"
BRINGUP_COMMAND ??= ""
LDS_MODEL ??= ""
CAMERA_SUPPORT ??= "0"
OPENCR_SUPPORT ??= "0"

# Tailscale
TAILSCALE_ENABLED ??= "1"
TAILSCALE_USE_HOSTNAME ??= "1"

# Extra companion-computer tools (default: all enabled)
DEV_TOOLS_ENABLED ??= "1"
PYTHON_TOOLS_ENABLED ??= "1"
RESEARCH_TOOLS_ENABLED ??= "1"

# Network (multiple WiFi networks supported)
WIFI_SSID_0 ??= ""
WIFI_PASS_0 ??= ""
WIFI_SSID_1 ??= ""
WIFI_PASS_1 ??= ""
WIFI_SSID_2 ??= ""
WIFI_PASS_2 ??= ""

# Image features common to all robot images
IMAGE_FEATURES:append = " \
    ssh-server-openssh \
"

DEV_TOOLS_PKGS = "packagegroup-core-buildessential gcc g++ clang cmake cargo rust"
PYTHON_TOOLS_PKGS = "python3 python3-pip python3-venv"
RESEARCH_TOOLS_PKGS = "git curl wget htop net-tools iproute2 usbutils i2c-tools vim-tiny rsync ca-certificates iw"

IMAGE_INSTALL:append = " \
    robot-user \
    robot-config \
    robot-firstboot \
    common-packages \
    tailscale \
    ${@d.getVar('DEV_TOOLS_PKGS') if d.getVar('DEV_TOOLS_ENABLED') == '1' else ''} \
    ${@d.getVar('PYTHON_TOOLS_PKGS') if d.getVar('PYTHON_TOOLS_ENABLED') == '1' else ''} \
    ${@d.getVar('RESEARCH_TOOLS_PKGS') if d.getVar('RESEARCH_TOOLS_ENABLED') == '1' else ''} \
"


