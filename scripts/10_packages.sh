#!/bin/bash
set -eux -o pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo -e "\e[1;32mUpdating Packages\e[0m"
apt-get update -y
apt-get upgrade -y
apt-get auto-remove -y
apt-get install -y network-manager git curl ssh nano ffmpeg
