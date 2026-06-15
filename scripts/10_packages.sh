#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mUpdating Packages\e[0m"
apt-get -y update
apt-get -y auto-remove
apt-get -y install git curl ssh nano ffmpeg openssh-server locales pip software-properties-common

apt-get -y install meson ninja-build

