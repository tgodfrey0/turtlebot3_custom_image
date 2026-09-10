# tailscale_%.bbappend - Tailscale hardening for robot images
#
# Ensure tailscaled starts after systemd-resolved so it runs in
# systemd-resolved DNS mode (upstreams from DHCP/netplan) instead of
# direct-file mode, which takes over /etc/resolv.conf and can leave
# MagicDNS without a working upstream on networks that block public DNS.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append = " file://tailscaled-resolved.conf"

do_install:append() {
    install -d ${D}${systemd_unitdir}/system/tailscaled.service.d
    install -m 0644 ${UNPACKDIR}/tailscaled-resolved.conf \
        ${D}${systemd_unitdir}/system/tailscaled.service.d/zz-resolved.conf
}

FILES:${PN} += "${systemd_unitdir}/system/tailscaled.service.d/zz-resolved.conf"