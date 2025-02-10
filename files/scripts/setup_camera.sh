#!/bin/bash
set -eux -o pipefail

if [[ -f /home/robot/.setup_camera ]]; then
  echo -e 'start_x=1\ngpu_mem=128' >> /boot/firmware/config.txt
  rm /home/robot/.setup_camera
fi


#TODO Schedule restart