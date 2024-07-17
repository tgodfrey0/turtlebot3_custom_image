#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mConfiguring system\e[0m"
echo -e 'APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";' > /etc/apt/apt.conf.d/20auto-upgrades
systemctl mask systemd-networkd-wait-online.service
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target