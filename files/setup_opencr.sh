#!/bin/bash
set -eux -o pipefail

if [[ -f /root/.setup_opencr ]]; then
  export OPENCR_PORT=/dev/ttyACM0
  export OPENCR_MODEL=waffle

  cd /root/opencr_update
  ./update.sh $OPENCR_PORT $OPENCR_MODEL.opencr

  rm /root/.setup_opencr
fi
