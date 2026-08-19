# tailscale_%.bbappend - Enable Tailscale VPN service
#
# Ensures tailscaled is enabled and starts on boot.
# The first-boot auth is handled by setup_tailscale.sh in robot-firstboot.

SUMMARY = "Tailscale VPN setup"
DESCRIPTION = "Enables Tailscale VPN service for first-boot connection"

# Enable the tailscaled service to start on boot
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# Ensure tailscale is installed
RDEPENDS:${PN} += " \
    bash \
    iptables \
"
