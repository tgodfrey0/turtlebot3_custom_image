# robot-config_1.0.bb - Robot configuration recipe
#
# Writes build-time configuration to /etc/robot-config/ and
# sets up first-boot marker files and network config.
# Replaces the config-writing parts of Packer provisioner scripts.

SUMMARY = "Robot configuration"
DESCRIPTION = "Writes robot configuration files and first-boot markers"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://networks.json \
"

# Robot configuration variables
ROBOT_USER ??= "robot"
ROBOT_TYPE ??= "generic"
ROBOT_MODEL ??= ""
BRINGUP_COMMAND ??= ""
ROS_DOMAIN_ID ??= "0"
LDS_MODEL ??= ""
TAILSCALE_USE_HOSTNAME ??= "1"
CAMERA_SUPPORT ??= "0"

# WiFi networks (up to 3)
WIFI_SSID_0 ??= ""
WIFI_PASS_0 ??= ""
WIFI_SSID_1 ??= ""
WIFI_PASS_1 ??= ""
WIFI_SSID_2 ??= ""
WIFI_PASS_2 ??= ""

do_install() {
    # Create /etc/robot-config directory
    install -d -m 0755 ${D}${sysconfdir}/robot-config

    # Write robot type and model
    echo "${ROBOT_TYPE}" > ${D}${sysconfdir}/robot-config/robot_type
    echo "${ROBOT_MODEL}" > ${D}${sysconfdir}/robot-config/robot_model

    # Write bringup command
    echo "${BRINGUP_COMMAND}" > ${D}${sysconfdir}/robot-config/bringup_command

    # Write ROS domain ID
    echo "${ROS_DOMAIN_ID}" > ${D}${sysconfdir}/robot-config/ros_domain_id

    # Write LDS model
    echo "${LDS_MODEL}" > ${D}${sysconfdir}/robot-config/lds_model

    # Write workspace path (colcon workspace for ROS builds)
    echo "/home/${ROBOT_USER}/colcon_ws" > ${D}${sysconfdir}/robot-config/workspace_path

    # Create user config directory
    install -d -m 0755 ${D}/home/${ROBOT_USER}/.config

    # Write network configuration as JSON
    # This is read by gen_netplan.py at first boot
    if [ -n "${WIFI_SSID_0}" ]; then
        cat > ${D}/home/${ROBOT_USER}/.config/networks.json << 'NETWORKS_EOF'
[
NETWORKS_EOF

        # Write first network
        if [ -n "${WIFI_SSID_0}" ]; then
            echo "  {\"ssid\": \"${WIFI_SSID_0}\", \"password\": \"${WIFI_PASS_0}\"}" >> ${D}/home/${ROBOT_USER}/.config/networks.json
        fi

        # Write second network if present
        if [ -n "${WIFI_SSID_1}" ]; then
            echo "  ,{\"ssid\": \"${WIFI_SSID_1}\", \"password\": \"${WIFI_PASS_1}\"}" >> ${D}/home/${ROBOT_USER}/.config/networks.json
        fi

        # Write third network if present
        if [ -n "${WIFI_SSID_2}" ]; then
            echo "  ,{\"ssid\": \"${WIFI_SSID_2}\", \"password\": \"${WIFI_PASS_2}\"}" >> ${D}/home/${ROBOT_USER}/.config/networks.json
        fi

        cat >> ${D}/home/${ROBOT_USER}/.config/networks.json << 'NETWORKS_EOF2'
]
NETWORKS_EOF2
    fi

    # Create first-boot marker files
    # These are deleted by the first-boot scripts after they run
    touch ${D}/home/${ROBOT_USER}/.setup_hostname
    touch ${D}/home/${ROBOT_USER}/.setup_firewall
    touch ${D}/home/${ROBOT_USER}/.setup_tailscale

    if [ -n "${WIFI_SSID_0}" ]; then
        touch ${D}/home/${ROBOT_USER}/.setup_network
    fi

    if [ "${CAMERA_SUPPORT}" = "1" ]; then
        touch ${D}/home/${ROBOT_USER}/.setup_camera
    fi
}

FILES:${PN} = " \
    ${sysconfdir}/robot-config/* \
    /home/${ROBOT_USER}/.config/* \
    /home/${ROBOT_USER}/.setup_* \
"

# Ensure config directory exists before this recipe
DEPENDS += "robot-user"
