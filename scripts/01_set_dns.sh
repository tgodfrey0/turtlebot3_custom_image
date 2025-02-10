#!/bin/bash
set -eux -o pipefail

mkdir -p /run/systemd/resolve
echo '# this file provisioned by Packer' > /run/systemd/resolve/stub-resolv.conf
echo 'nameserver 152.78.110.110' >> /run/systemd/resolve/stub-resolv.conf
echo 'nameserver 152.78.111.81' >> /run/systemd/resolve/stub-resolv.conf
echo 'nameserver 8.8.8.8' >> /run/systemd/resolve/stub-resolv.conf
