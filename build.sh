#!/bin/bash

SKIP_COMPRESSION="false"
ADD_CONNECTION="false"
# CONNECTION_NAME=""
# CONNECTION_TYPE=""
# INTERFACE=""
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
    waffle)
      MODEL="waffle"
      ;;
    burger)
      MODEL="burger"
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

NAME="tb3"
VERSION="$(git describe --tags --always)"

# rm -f *-image-*.img.xz
# rm -f *-image-*.img

if [ "$ADD_CONNECTION" = "true" ]; then
  echo "Adding network connection..."

  read -r -p "SSID: " SSID
  read -r -s -p "Password (Leave blank if N/A): " PASSWORD
fi

OPENCR_MODEL=${MODEL}

if [ "$MODEL" = "waffle" ]; then
  TURTLEBOT3_MODEL=${MODEL}_pi
else
  TURTLEBOT3_MODEL=${MODEL}
fi

echo "
Configuration:
--------------
NAME: $NAME
VERSION: $VERSION
SKIP_COMPRESSION: $SKIP_COMPRESSION
OPENCR_MODEL: $OPENCR_MODEL
TURTLEBOT3_MODEL: $TURTLEBOT3_MODEL
ADD_CONNECTION: $ADD_CONNECTION
SSID: $SSID
PASSWORD: ${PASSWORD//?/*}

Are these settings correct? (y/n): "
read -r confirmation



if [[ $confirmation != [Yy]* ]]; then
  echo "Aborting operation."
  exit 1
fi

echo "Proceeding with the build process..."

FILE="./build/$NAME-$TURTLEBOT3_MODEL-image-$VERSION.img*"
if [[ -f "$FILE" ]]; then
  rm "$FILE"
fi

podman pull mkaczanowski/packer-builder-arm:latest

sudo podman run --rm --privileged \
    --pid=host \
    -v /dev:/dev \
    -v ${PWD}:/build \
    mkaczanowski/packer-builder-arm:latest \
    build \
    -var "NAME=${NAME}" \
    -var "VERSION=${VERSION}" \
    -var "SKIP_COMPRESSION=${SKIP_COMPRESSION}" \
    -var "OPENCR_MODEL=${OPENCR_MODEL}" \
    -var "TURTLEBOT3_MODEL=${TURTLEBOT3_MODEL}" \
    -var "ADD_CONNECTION=${ADD_CONNECTION}" \
    -var "SSID=${SSID}"\
    -var "PASSWORD=${PASSWORD}"\
    packer_ubuntu_server_2204.json


    # -var "CONNECTION_NAME=${CONNECTION_NAME}" \
    # -var "CONNECTION_TYPE=${CONNECTION_TYPE}" \
    # -var "INTERFACE=${INTERFACE}" \
