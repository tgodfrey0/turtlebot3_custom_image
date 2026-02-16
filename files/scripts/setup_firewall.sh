#!/bin/bash
set -eux -o pipefail

USERNAME="${USERNAME}"

if [[ -f /home/${USERNAME}/.setup_firewall ]]; then
  ufw allow ssh
  ufw allow 22
  rm /home/${USERNAME}/.setup_firewall
fi
