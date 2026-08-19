#!/usr/bin/env bash
set -euo pipefail

# build.sh - small kas/Yocto helper wrapper
# Usage: ./build.sh --profile <generic|turtlebot3> [--machine MACHINE] [--authkey KEY] [--hostname HOST] [--no-build]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOPDIR=${SCRIPT_DIR}
TEMPLATE=${TOPDIR}/conf/local.conf.template
LOCAL_CONF=${TOPDIR}/conf/local.conf
PROFILE="${1:-generic}"
NO_BUILD=0
DRY_RUN=0

# parse simple args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    --machine) MACHINE_VAL="$2"; shift 2;;
    --authkey) TAILSCALE_AUTHKEY_VAL="$2"; shift 2;;
    --hostname) HOSTNAME_PREFIX_VAL="$2"; shift 2;;
    --image-name) IMAGE_NAME_VAL="$2"; shift 2;;
    --no-build) NO_BUILD=1; shift 1;;
    --dry-run) DRY_RUN=1; shift 1;;
    --export-only) NO_BUILD=1; DRY_RUN=0; shift 1;;
    --help) echo "Usage: $0 --profile <generic|turtlebot3> [--machine MACHINE] [--authkey KEY] [--hostname PREFIX] [--no-build] [--dry-run]"; exit 0;;
    *) shift 1;;
  esac
done

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Error: template ${TEMPLATE} not found" >&2
  exit 2
fi

# copy template to conf/local.conf
cp "${TEMPLATE}" "${LOCAL_CONF}"

# helper to set a key in local.conf (replace first matching line or append if missing)
set_kv() {
  key="$1"
  val="$2"
  # escape slashes for sed
  esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
  if grep -q "^${key}" "${LOCAL_CONF}"; then
    sed -i "s|^${key}.*|${key} = \"${esc}\"|" "${LOCAL_CONF}"
  else
    echo "${key} = \"${val}\"" >> "${LOCAL_CONF}"
  fi
}

[ -n "${MACHINE_VAL:-}" ] && set_kv MACHINE "${MACHINE_VAL}"
[ -n "${TAILSCALE_AUTHKEY_VAL:-}" ] && set_kv TAILSCALE_AUTHKEY "${TAILSCALE_AUTHKEY_VAL}"
[ -n "${HOSTNAME_PREFIX_VAL:-}" ] && set_kv HOSTNAME_PREFIX "${HOSTNAME_PREFIX_VAL}"
[ -n "${IMAGE_NAME_VAL:-}" ] && set_kv IMAGE_NAME "${IMAGE_NAME_VAL}"

# log the generated conf location
echo "Generated ${LOCAL_CONF} (profile=${PROFILE})"

# show a short preview if dry-run
if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "--- preview ${LOCAL_CONF} ---"
  sed -n '1,240p' "${LOCAL_CONF}"
  exit 0
fi

# run kas build unless NO_BUILD
KAS_CMD=(kas build "configs/kas/${PROFILE}.yml")
if [[ ${NO_BUILD} -eq 1 ]]; then
  echo "Exported conf and skipping build. Run: \
    ${KAS_CMD[*]}"
  exit 0
fi

echo "Running: ${KAS_CMD[*]}"
"${KAS_CMD[@]}"
