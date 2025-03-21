#!/bin/bash
set -eux -o pipefail

if [[ -f /home/robot/.setup_firewall ]]; then
  ufw allow ssh
  ufw allow 22
  rm /home/robot/.setup_firewall
fi
