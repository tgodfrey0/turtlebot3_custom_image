#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo -e "\e[1;32mUpdating Packages\e[0m"
apt update -y
apt upgrade -y
apt auto-remove -y
apt install -y network-manager git curl ssh