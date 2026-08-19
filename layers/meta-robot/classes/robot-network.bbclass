# robot-network.bbclass - Network and connectivity helpers
#
# Handles WiFi first-boot setup and Tailscale VPN configuration.

# Network configuration is written to JSON at build time,
# then read by setup_network.sh at first boot via gen_netplan.py.

# WiFi network files are deployed by robot-config recipe.
# Tailscale auth key is deployed by tailscale bbappend.
