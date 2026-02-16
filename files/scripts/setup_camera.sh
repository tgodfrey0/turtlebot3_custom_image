#!/bin/bash
set -eux -o pipefail

USERNAME="${USERNAME}"

if [[ -f /home/${USERNAME}/.setup_camera ]]; then
  echo -e 'start_x=1\ngpu_mem=128' >> /boot/firmware/config.txt
  rm /home/${USERNAME}/.setup_camera
fi


#TODO Schedule restart