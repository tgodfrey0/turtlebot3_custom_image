#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mConfiguring system\e[0m"
echo -e 'APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";' > /etc/apt/apt.conf.d/20auto-upgrades
systemctl mask systemd-networkd-wait-online.service
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
systemctl enable sshd

sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication no/' /etc/ssh/sshd_config

touch /home/robot/.setup_firewall
chmod +x /home/robot/setup_scripts/setup_firewall.sh
systemctl enable firewall_setup.service

echo "export NETWORK_SSID=$SSID" | tee -a /etc/profile.d/91-net-vars-profile.sh > /dev/null
echo "export NETWORK_PASSWORD=$PASSWORD" | tee -a /etc/profile.d/91-net-vars-profile.sh > /dev/null
chmod 755 /etc/profile.d/91-net-vars-profile.sh

sed -i 's/^XKBLAYOUT=".*"/XKBLAYOUT="gb"/' /etc/default/keyboard
