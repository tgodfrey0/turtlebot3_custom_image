SUMMARY = "Tailscale client and daemon"
DESCRIPTION = "Tailscale is a mesh VPN built on WireGuard. Installs prebuilt static binary."
HOMEPAGE = "https://tailscale.com"
SECTION = "networking"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = "https://pkgs.tailscale.com/stable/tailscale_${PV}_arm64.tgz;name=tailscale"
SRC_URI[tailscale.sha256sum] = "SKIP"

S = "${WORKDIR}"

# No compilation needed - prebuilt binary
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/tailscale_${PV}/tailscale ${D}${bindir}/tailscale
    install -m 0755 ${WORKDIR}/tailscale_${PV}/tailscaled ${D}${bindir}/tailscaled

    install -d ${D}${systemd_system_unitdir}
    cat > ${D}${systemd_system_unitdir}/tailscaled.service <<EOF
[Unit]
Description=Tailscale node agent
Documentation=https://tailscale.com/kb/
Wants=network-pre.target
After=network-pre.target network.service

[Service]
Type=simple
ExecStart=${bindir}/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

inherit systemd

SYSTEMD_SERVICE:${PN} = "tailscaled.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} += " \
    bash \
    iptables \
    wireguard-tools \
"

FILES:${PN} = "${bindir}/tailscale*"
