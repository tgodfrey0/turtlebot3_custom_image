#!/bin/bash
set -eux -o pipefail

if [[ -f /root/.setup_hostname ]]; then
  NEW_HOSTNAME="turtlebot_$(ip -brief link show | grep -v LOOPBACK | grep -v "DOWN" | head -n 1 | sed 's/ /\n/g' | grep -v "^$" | head -n 3 | tail -n 1 | cut -d ':' -f4- | tr ":" "_")"
  echo -e "\e[1;32mSetting hostname to $NEW_HOSTNAME\e[0m"
  cat /etc/cloud/cloud.cfg | sed 's/preserve_hostname: false/preserve_hostname: true' > /etc/cloud/cloud.cfg
  hostnamectl set-hostname $NEW_HOSTNAME
  rm /root/.setup_hostname
fi
