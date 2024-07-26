#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mUpdating Packages\e[0m"
apt-get -y update
apt-get -y upgrade
apt-get -y auto-remove
apt-get -y install network-manager git curl ssh nano ffmpeg openssh-server locales

