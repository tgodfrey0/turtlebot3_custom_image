#!/usr/bin/env bash
set -euo pipefail

# build.sh - small kas/Yocto helper wrapper
# Usage: ./build.sh --config <kas-profile.yml> [--machine MACHINE] [--authkey KEY] [--hostname HOST] [--no-build]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOPDIR=${SCRIPT_DIR}
KAS_DIR=${TOPDIR}/configs/kas
# kas REGENERATES build/conf/local.conf on every run, so all settings live in
# the shared fragment; --config selects which profile yml gets built.
SETTINGS_CONF=${KAS_DIR}/robot-settings.yml
# secrets (authkey, passwords) go here - gitignored, overrides robot-settings
SECRETS_CONF=${KAS_DIR}/local-overrides.yml
CONFIG=""
NO_BUILD=0
DRY_RUN=0
OUTPUT_ROOT="${TOPDIR}/output"
WIFI_ARGS=()

# parse simple args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2;;
    --machine) MACHINE_VAL="$2"; shift 2;;
    --authkey) TAILSCALE_AUTHKEY_VAL="$2"; shift 2;;
    --hostname) HOSTNAME_PREFIX_VAL="$2"; shift 2;;
    --image-name) IMAGE_NAME_VAL="$2"; shift 2;;
    --robot-type) ROBOT_TYPE_VAL="$2"; shift 2;;
    --robot-model) ROBOT_MODEL_VAL="$2"; shift 2;;
    --robot-user) ROBOT_USER_VAL="$2"; shift 2;;
    --robot-pass) ROBOT_PASS_VAL="$2"; shift 2;;
    --tailscale-enabled) TAILSCALE_ENABLED_VAL="$2"; shift 2;;
    --ros-enabled) ROS_ENABLED_VAL="$2"; shift 2;;
    --ros-distro) ROS_DISTRO_VAL="$2"; shift 2;;
    --mavlink-enabled) MAVLINK_ENABLED_VAL="$2"; shift 2;;
    --camera-enabled) CAMERA_SUPPORT_VAL="$2"; shift 2;;
    --opencr-enabled) OPENCR_SUPPORT_VAL="$2"; shift 2;;
    --wifi) WIFI_ARGS+=("$2" "$3"); shift 3;;
    --outdir) OUTPUT_ROOT="$2"; shift 2;;
    --no-build) NO_BUILD=1; shift 1;;
    --dry-run) DRY_RUN=1; shift 1;;
    --export-only) NO_BUILD=1; DRY_RUN=0; shift 1;;
    --help) echo "Usage: $0 --config <path> [--machine MACHINE] [--authkey KEY] [--hostname PREFIX] [--image-name NAME] [--robot-user USER] [--robot-pass PASS] [--tailscale-enabled 0|1] [--ros-distro DISTRO] [--outdir DIR] [--no-build] [--dry-run]"; exit 0;;
    *) shift 1;;
  esac
done

if [[ -z "${CONFIG}" ]]; then
  echo "Error: --config <path> is required (e.g. configs/kas/build-config.yml)" >&2
  exit 2
fi

if [[ ! -f "${TOPDIR}/${CONFIG}" && ! -f "${CONFIG}" ]]; then
  echo "Error: kas config ${CONFIG} not found" >&2
  exit 2
fi

# profile yml (machine/distro/target scalars live here)
CONFIG=$(realpath "${CONFIG}")
PROFILE_CONF="${CONFIG}"

if [[ ! -f "${SETTINGS_CONF}" ]]; then
  echo "Error: settings fragment ${SETTINGS_CONF} not found" >&2
  exit 2
fi

# ensure the untracked overrides file exists (kas fails on missing includes)
if [[ ! -f "${SECRETS_CONF}" ]]; then
  cat > "${SECRETS_CONF}" <<'EOF'
# local-overrides.yml - UNTRACKED machine-local secrets (auto-created by build.sh)
#
# Values here override robot-settings.yml. Never commit this file - it holds
# your Tailscale authkey, WiFi passwords and robot password.

header:
  version: 14

local_conf_header:
  local-secrets: |
    ROBOT_PASS = ""
    TAILSCALE_AUTHKEY = ""
    WIFI_PASS_0 = ""
    WIFI_PASS_1 = ""
    WIFI_PASS_2 = ""
EOF
fi

# helper to set a KEY = "value" line inside the shared settings fragment
set_kv() {
  key="$1"
  val="$2"
  esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
  if grep -q "^[[:space:]]*${key} " "${SETTINGS_CONF}"; then
    sed -i "s|^[[:space:]]*${key} .*|    ${key} = \"${esc}\"|" "${SETTINGS_CONF}"
  else
    echo "Warning: ${key} not present in ${SETTINGS_CONF}; add it manually" >&2
  fi
}

# secrets must never land in the tracked fragment
set_secret() {
  key="$1"
  val="$2"
  esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
  if grep -q "^[[:space:]]*${key} " "${SECRETS_CONF}"; then
    sed -i "s|^[[:space:]]*${key} .*|    ${key} = \"${esc}\"|" "${SECRETS_CONF}"
  else
    echo "Warning: ${key} not present in ${SECRETS_CONF}; add it manually" >&2
  fi
}

# top-level yaml scalars (machine:/distro:/target:) are edited per-profile
set_yaml_scalar() {
  key="$1"
  val="$2"
  if grep -q "^${key}:" "${PROFILE_CONF}"; then
    sed -i "s|^${key}: .*|${key}: ${val}|" "${PROFILE_CONF}"
  else
    sed -i "4i ${key}: ${val}" "${PROFILE_CONF}"
  fi
}

[ -n "${MACHINE_VAL:-}" ] && set_yaml_scalar machine "${MACHINE_VAL}"
[ -n "${TAILSCALE_AUTHKEY_VAL:-}" ] && set_secret TAILSCALE_AUTHKEY "${TAILSCALE_AUTHKEY_VAL}"
[ -n "${HOSTNAME_PREFIX_VAL:-}" ] && set_kv HOSTNAME_PREFIX "${HOSTNAME_PREFIX_VAL}"
[ -n "${IMAGE_NAME_VAL:-}" ] && set_kv IMAGE_NAME "${IMAGE_NAME_VAL}"
[ -n "${ROBOT_TYPE_VAL:-}" ] && set_kv ROBOT_TYPE "${ROBOT_TYPE_VAL}"
[ -n "${ROBOT_MODEL_VAL:-}" ] && set_kv ROBOT_MODEL "${ROBOT_MODEL_VAL}"
[ -n "${ROBOT_USER_VAL:-}" ] && set_kv ROBOT_USER "${ROBOT_USER_VAL}"
[ -n "${ROBOT_PASS_VAL:-}" ] && set_secret ROBOT_PASS "${ROBOT_PASS_VAL}"
[ -n "${TAILSCALE_ENABLED_VAL:-}" ] && set_kv TAILSCALE_ENABLED "${TAILSCALE_ENABLED_VAL}"
[ -n "${ROS_ENABLED_VAL:-}" ] && set_kv ROS_ENABLED "${ROS_ENABLED_VAL}"
[ -n "${ROS_DISTRO_VAL:-}" ] && set_kv ROS_DISTRO "${ROS_DISTRO_VAL}"
[ -n "${MAVLINK_ENABLED_VAL:-}" ] && set_kv MAVLINK_ENABLED "${MAVLINK_ENABLED_VAL}"
[ -n "${MAVLINK_ENABLED_VAL:-}" ] && set_kv MAVLINK_ENABLED "${MAVLINK_ENABLED_VAL}"
[ -n "${CAMERA_SUPPORT_VAL:-}" ] && set_kv CAMERA_SUPPORT "${CAMERA_SUPPORT_VAL}"
[ -n "${OPENCR_SUPPORT_VAL:-}" ] && set_kv OPENCR_SUPPORT "${OPENCR_SUPPORT_VAL}"
# WiFi settings from WIFI_ARGS array
WIFI_IDX=0
WIFI_SSID_VALS=()
WIFI_PASS_VALS=()
while [[ ${#WIFI_ARGS[@]} -gt 0 ]]; do
  WIFI_SSID_VALS+=("${WIFI_ARGS[0]}")
  WIFI_PASS_VALS+=("${WIFI_ARGS[1]}")
  set_kv "WIFI_SSID_${WIFI_IDX}" "${WIFI_ARGS[0]}"
  set_secret "WIFI_PASS_${WIFI_IDX}" "${WIFI_ARGS[1]}"
  WIFI_ARGS=("${WIFI_ARGS[@]:2}")
  WIFI_IDX=$((WIFI_IDX + 1))
done
WIFI_COUNT=${WIFI_IDX}

# log the generated conf location
echo "Updated ${SETTINGS_CONF} + ${PROFILE_CONF} (config=${CONFIG})"

# show a short preview if dry-run
if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "--- preview ${PROFILE_CONF} ---"
  sed -n '1,240p' "${PROFILE_CONF}"
  echo "--- preview ${SETTINGS_CONF} (robot-settings block) ---"
  sed -n '/robot-settings: |/,$p' "${SETTINGS_CONF}"
  exit 0
fi

# helper to read a key (checks the secrets override file, then settings)
get_kv() {
  key="$1"
  for f in "${SECRETS_CONF}" "${SETTINGS_CONF}"; do
    if grep -q "^[[:space:]]*${key} " "${f}"; then
      grep "^[[:space:]]*${key} " "${f}" | head -n1 | sed -E 's/^[^=]+= *"(.*)"/\1/'
      return
    fi
  done
  echo ""
}

write_summary() {
  TS=$(date -u +"%Y%m%dT%H%M%SZ")
  # include a short git hash for traceability (kept in summary content)
  GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")

  IMAGE_NAME_VAL=$(get_kv IMAGE_NAME)
  ROBOT_USER_VAL=$(get_kv ROBOT_USER)
  ROBOT_PASS_VAL=$(get_kv ROBOT_PASS)
  ROBOT_TYPE_VAL=$(get_kv ROBOT_TYPE)
  HOSTNAME_PREFIX_VAL=$(get_kv HOSTNAME_PREFIX)
  TAILSCALE_ENABLED_VAL=$(get_kv TAILSCALE_ENABLED)
  ROS_ENABLED_VAL=$(get_kv ROS_ENABLED)
  MAVLINK_ENABLED_VAL=$(get_kv MAVLINK_ENABLED)
  CAMERA_SUPPORT_VAL=$(get_kv CAMERA_SUPPORT)
  OPENCR_SUPPORT_VAL=$(get_kv OPENCR_SUPPORT)

  # Find generated images in the deploy dir (real files only; stable-name
  # symlinks are skipped so we copy the timestamped artifacts once)
  IMAGES=$(find . -path "*/tmp/deploy/images/*" -type f -name "${IMAGE_NAME_VAL}*" \( -name "*.wic" -o -name "*.wic.bz2" -o -name "*.wic.gz" -o -name "*.img" -o -name "*.zip" \) -print 2>/dev/null || true)
  if [[ -z "${IMAGE_NAME_VAL}" ]]; then
    IMAGE_NAME_VAL="unnamed"
  fi
  TARGET_DIR="${OUTPUT_ROOT}/${IMAGE_NAME_VAL}-${GIT_HASH}"
  mkdir -p "${TARGET_DIR}"

  # process images and copy artifacts into OUTPUT_ROOT/<image_name>-<git_hash>/
  if [[ -n "${IMAGES}" && ${NO_BUILD} -eq 0 ]]; then
    while IFS= read -r img; do
      img_dir=$(dirname "${img}")
      bn=$(basename "${img}")
      base_noext="${bn%.*}"

      # copy the main image keeping its original filename
      cp -f "${img}" "${TARGET_DIR}/${bn}"

      # copy related auxiliary files with same base name
      for aux in "${img_dir}/${base_noext}"*; do
        if [[ -f "${aux}" && "${aux}" != "${img}" ]]; then
          cp -f "${aux}" "${TARGET_DIR}/$(basename "${aux}")"
        fi
      done

      echo "Copied image artifacts to ${TARGET_DIR}/"
    done <<< "${IMAGES}"
  fi

  # write parameter summary directly into the artifact directory
  {
    echo "timestamp: ${TS}"
    echo "config: ${CONFIG}"
    echo "machine: ${MACHINE_VAL:-${MACHINE:-}}"
    echo "image_name: ${IMAGE_NAME_VAL}"
    echo "robot_type: ${ROBOT_TYPE_VAL}"
    echo "robot_user: ${ROBOT_USER_VAL}"
    echo "robot_pass: ${ROBOT_PASS_VAL}"
    echo "hostname_prefix: ${HOSTNAME_PREFIX_VAL}"
    echo "tailscale_enabled: ${TAILSCALE_ENABLED_VAL}"
    echo "ros_enabled: ${ROS_ENABLED_VAL}"
    echo "mavlink_enabled: ${MAVLINK_ENABLED_VAL}"
    echo "camera_support: ${CAMERA_SUPPORT_VAL}"
    echo "opencr_support: ${OPENCR_SUPPORT_VAL}"
    for ((i=0; i<${#WIFI_SSID_VALS[@]}; i++)); do
      echo "wifi_${i}_ssid: ${WIFI_SSID_VALS[$i]}"
      echo "wifi_${i}_pass: ${WIFI_PASS_VALS[$i]}"
    done
    echo "kas_command: kas build ${CONFIG}"
    echo "git_hash: ${GIT_HASH}"
  } > "${TARGET_DIR}/${IMAGE_NAME_VAL}-parameter_summary"
  echo "Wrote build summary to ${TARGET_DIR}/${IMAGE_NAME_VAL}-parameter_summary"
}

# run kas build unless NO_BUILD (always from repo root so build/, output/
# discovery and relative --config paths behave the same for CLI and TUI)
cd "${TOPDIR}"
KAS_CMD=(kas build "${CONFIG}")
if [[ ${NO_BUILD} -eq 1 ]]; then
  echo "Exported conf and skipping build. Run: \
    ${KAS_CMD[*]}"
  write_summary || true
  exit 0
fi

echo "Running: ${KAS_CMD[*]}"
"${KAS_CMD[@]}"
RC=$?
if [[ ${RC} -eq 0 ]]; then
  echo "Build completed successfully"
  write_summary || true
else
  echo "Build failed (exit ${RC})"
fi
exit ${RC}
