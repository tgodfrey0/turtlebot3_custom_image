#!/bin/bash
set -eux -o pipefail

USERNAME="${USERNAME}"

if [[ -f /home/${USERNAME}/.setup_hostname ]]; then
  pip install --no-input uuid
  NEW_HOSTNAME=$(python3 /home/${USERNAME}/setup_scripts/get_hostname.py)
  echo -e "\e[1;32mSetting hostname to $NEW_HOSTNAME\e[0m"
  sed -i 's/preserve_hostname: false/preserve_hostname: true/' /etc/cloud/cloud.cfg
  hostnamectl set-hostname $NEW_HOSTNAME
  rm /home/${USERNAME}/.setup_hostname
fi
