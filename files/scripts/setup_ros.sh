#!/bin/bash
set -eux -o pipefail

if [[ -f /home/robot/.setup_keyboard ]]; then
  localectl set-keymap gb

  rm /home/robot/.setup_keyboard
fi
