#!/bin/bash
set -eux -o pipefail

if [[ -f /root/.setup_hostname ]]; then
  pip install uuid
  NEW_HOSTNAME=$(python /root/setup_scripts/get_hostname.py)
  echo -e "\e[1;32mSetting hostname to $NEW_HOSTNAME\e[0m"
  cat /etc/cloud/cloud.cfg | sed 's/preserve_hostname: false/preserve_hostname: true' > /etc/cloud/cloud.cfg
  hostnamectl set-hostname $NEW_HOSTNAME
  rm /root/.setup_hostname
fi
