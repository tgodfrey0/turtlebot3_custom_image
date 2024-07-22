#!/bin/bash
set -eux -o pipefail

echo -e "\e[1;32mUpdating Packages\e[0m"
apt-get update -y
apt-get upgrade -y
apt-get auto-remove -y
apt-get install -y network-manager git curl ssh nano ffmpeg openssh-server

#TODO Change nointeractive for all scripts
