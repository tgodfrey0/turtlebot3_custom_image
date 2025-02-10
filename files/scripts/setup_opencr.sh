#!/bin/bash
set -eux -o pipefail

if [[ -f /home/robot/.setup_opencr ]]; then
  export OPENCR_PORT=/dev/ttyACM0

  cd /home/robot/opencr_update
  ./update.sh $OPENCR_PORT $OPENCR_MODEL.opencr

  rm /home/robot/.setup_opencr
fi
