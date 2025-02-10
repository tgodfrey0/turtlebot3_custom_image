#!/bin/bash
set -eux -o pipefail

if [[ -f /home/robot/.setup_firewall ]]; then
  ufw allow ssh
  rm /home/robot/.setup_firewall
fi


