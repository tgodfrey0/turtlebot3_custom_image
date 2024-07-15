#!/bin/bash
if [ "$1" == "nocompress" ]; then
    SKIP_COMPRESSION="true"
else
    SKIP_COMPRESSION="false"
fi

NAME="tb3"
VERSION="$(git describe --tags --always)"

rm -f *-image-*.iso.xz
rm -f *-image-*.iso

docker run --rm --privileged \
    -v /dev:/dev \
    -v ${PWD}:/build \
    mkaczanowski/packer-builder-arm:latest \
    build \
    -var "NAME=${NAME}" \
    -var "VERSION=${VERSION}" \
    -var "SKIP_COMPRESSION=${SKIP_COMPRESSION}" \
    packer_ubuntu_server_2204.json