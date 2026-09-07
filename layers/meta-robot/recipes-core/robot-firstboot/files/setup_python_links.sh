#!/bin/bash
set -eu -o pipefail

read USERNAME < /etc/robot-user
if [[ ! -f "/home/${USERNAME}/.setup_python_links" ]]; then
    exit 0
fi

if command -v python3 >/dev/null 2>&1; then
    ln -sf "$(command -v python3)" "/usr/local/bin/python"
fi
if command -v pip3 >/dev/null 2>&1; then
    ln -sf "$(command -v pip3)" "/usr/local/bin/pip"
fi

rm -f "/home/${USERNAME}/.setup_python_links"
