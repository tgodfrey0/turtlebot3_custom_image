#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mConfiguring system\e[0m"
echo -e 'APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";' > /etc/apt/apt.conf.d/20auto-upgrades
systemctl mask systemd-networkd-wait-online.service
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
systemctl enable ssh

sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

USERNAME="${USERNAME:-robot}"

echo "Match User $USERNAME" | tee /etc/ssh/sshd_config.d/10-password-login-for-$USERNAME.conf > /dev/null
echo "    PasswordAuthentication yes" | tee -a /etc/ssh/sshd_config.d/10-password-login-for-$USERNAME.conf > /dev/null

touch /home/$USERNAME/.setup_firewall
chmod +x /home/$USERNAME/setup_scripts/setup_firewall.sh
systemctl enable firewall_setup.service

sed -i 's/^XKBLAYOUT=".*"/XKBLAYOUT="gb"/' /etc/default/keyboard
