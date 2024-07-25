#!/bin/bash
set -eux -o pipefail

if [[ -f /root/.setup_firewall ]]; then
  ufw allow ssh
  rm /root/.setup_firewall
fi


