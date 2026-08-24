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

IMAGE_INSTALL:append = " \
    robot-user \
    robot-config \
    robot-firstboot \
    common-packages \
    tailscale \
"


