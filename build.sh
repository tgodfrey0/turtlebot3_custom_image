#!/bin/bash

SKIP_COMPRESSION="false"
ADD_CONNECTION="false"
CONNECTION_NAME=""
CONNECTION_TYPE=""
INTERFACE=""
SSID=""
PASSWORD=""

for arg in "$@"; do
  case "$arg" in
    nocompress)
      SKIP_COMPRESSION="true"
      ;;
    addconnection)
      ADD_CONNECTION="true"
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

NAME="tb3"
VERSION="$(git describe --tags --always)"

rm -f *-image-*.img.xz
rm -f *-image-*.img

if [ "$ADD_CONNECTION" = "true" ]; then
  echo "Adding network connection..."

  # read -p "Connection name: " CONNECTION_NAME
  # read -p "Connection type (e.g., ethernet, wifi): " CONNECTION_TYPE
  # read -p "Interface name (e.g., eth0, wlp0s20f3): " INTERFACE
  read -p "SSID (Leave blank if ethernet): " SSID
  read -p -s "Password (Leave blank if N/A): " PASSWORD
fi

docker run --rm --privileged \
    -v /dev:/dev \
    -v ${PWD}:/build \
    mkaczanowski/packer-builder-arm:latest \
    build \
    -var "NAME=${NAME}" \
    -var "VERSION=${VERSION}" \
    -var "SKIP_COMPRESSION=${SKIP_COMPRESSION}" \
    -var "ADD_CONNECTION=${ADD_CONNECTION}" \
    -var "CONNECTION_NAME=${CONNECTION_NAME}" \
    -var "CONNECTION_TYPE=${CONNECTION_TYPE}" \
    -var "INTERFACE=${INTERFACE}" \
    -var "SSID=${SSID}" \
    -var "PASSWORD=${PASSWORD}" \
    packer_ubuntu_server_2204.json
