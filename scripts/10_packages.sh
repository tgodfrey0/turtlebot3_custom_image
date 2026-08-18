#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mUpdating Packages\e[0m"
apt-get -y update
apt-get -y auto-remove

# Install common packages for all robots (overridable list from config/env)
COMMON_PACKAGES="${COMMON_PACKAGES:-git curl ssh nano ffmpeg openssh-server locales pip software-properties-common meson ninja-build}"
apt-get -y install ${COMMON_PACKAGES}