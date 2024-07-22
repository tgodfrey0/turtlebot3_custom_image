#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mEnabling Pi Camera\e[0m"
echo -e 'start_x=1\ngpu_mem=128' >> /boot/firmware/config.txt
