#!/bin/bash
set -ex -o pipefail

USERNAME="${USERNAME}"

set +u
source /etc/profile.d/90-turtlebot-ros-profile.sh
set -u

if [[ -f /home/${USERNAME}/.setup_opencr ]]; then
  export OPENCR_PORT=/dev/ttyACM0

  cd /home/${USERNAME}/opencr_update
  ./update.sh $OPENCR_PORT $OPENCR_MODEL.opencr

  rm /home/${USERNAME}/.setup_opencr
fi
