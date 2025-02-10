#!/bin/bash
set -eux -o pipefail

if [[ -f /home/robot/.setup_hostname ]]; then
  pip install --no-input uuid
  NEW_HOSTNAME=$(python3 /home/robot/setup_scripts/get_hostname.py)
  echo -e "\e[1;32mSetting hostname to $NEW_HOSTNAME\e[0m"
  cat /etc/cloud/cloud.cfg | sed 's/preserve_hostname: false/preserve_hostname: true' > /etc/cloud/cloud.cfg
  hostnamectl set-hostname $NEW_HOSTNAME
  rm /home/robot/.setup_hostname
fi
