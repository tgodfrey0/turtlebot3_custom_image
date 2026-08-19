#!/usr/bin/env bash
set -euo pipefail

# build.sh - small kas/Yocto helper wrapper
# Usage: ./build.sh --profile <generic|turtlebot3> [--machine MACHINE] [--authkey KEY] [--hostname HOST] [--no-build]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOPDIR=${SCRIPT_DIR}
TEMPLATE=${TOPDIR}/conf/local.conf.template
LOCAL_CONF=${TOPDIR}/conf/local.conf
PROFILE="generic"
NO_BUILD=0
DRY_RUN=0
OUTPUT_ROOT="${TOPDIR}/output"

# parse simple args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    --machine) MACHINE_VAL="$2"; shift 2;;
    --authkey) TAILSCALE_AUTHKEY_VAL="$2"; shift 2;;
    --hostname) HOSTNAME_PREFIX_VAL="$2"; shift 2;;
    --image-name) IMAGE_NAME_VAL="$2"; shift 2;;
    --robot-type) ROBOT_TYPE_VAL="$2"; shift 2;;
    --robot-user) ROBOT_USER_VAL="$2"; shift 2;;
    --robot-pass) ROBOT_PASS_VAL="$2"; shift 2;;
    --tailscale-enabled) TAILSCALE_ENABLED_VAL="$2"; shift 2;;
    --ros-enabled) ROS_ENABLED_VAL="$2"; shift 2;;
    --mavlink-enabled) MAVLINK_ENABLED_VAL="$2"; shift 2;;
    --camera-enabled) CAMERA_SUPPORT_VAL="$2"; shift 2;;
    --opencr-enabled) OPENCR_SUPPORT_VAL="$2"; shift 2;;
    --wifi-ssid-0) WIFI_SSID_0_VAL="$2"; shift 2;;
    --wifi-pass-0) WIFI_PASS_0_VAL="$2"; shift 2;;
    --wifi-ssid-1) WIFI_SSID_1_VAL="$2"; shift 2;;
    --wifi-pass-1) WIFI_PASS_1_VAL="$2"; shift 2;;
    --wifi-ssid-2) WIFI_SSID_2_VAL="$2"; shift 2;;
    --wifi-pass-2) WIFI_PASS_2_VAL="$2"; shift 2;;
    --outdir) OUTPUT_ROOT="$2"; shift 2;;
    --no-build) NO_BUILD=1; shift 1;;
    --dry-run) DRY_RUN=1; shift 1;;
    --export-only) NO_BUILD=1; DRY_RUN=0; shift 1;;
    --help) echo "Usage: $0 --profile <generic|turtlebot3> [--machine MACHINE] [--authkey KEY] [--hostname PREFIX] [--image-name NAME] [--robot-user USER] [--robot-pass PASS] [--tailscale-enabled 0|1] [--ros-enabled 0|1] [--outdir DIR] [--no-build] [--dry-run]"; exit 0;;
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
# ROBOT_TYPE: prefer explicit value, else use PROFILE
if [ -n "${ROBOT_TYPE_VAL:-}" ]; then
  set_kv ROBOT_TYPE "${ROBOT_TYPE_VAL}"
else
  set_kv ROBOT_TYPE "${PROFILE}"
fi
[ -n "${ROBOT_USER_VAL:-}" ] && set_kv ROBOT_USER "${ROBOT_USER_VAL}"
[ -n "${ROBOT_PASS_VAL:-}" ] && set_kv ROBOT_PASS "${ROBOT_PASS_VAL}"
[ -n "${TAILSCALE_ENABLED_VAL:-}" ] && set_kv TAILSCALE_ENABLED "${TAILSCALE_ENABLED_VAL}"
[ -n "${ROS_ENABLED_VAL:-}" ] && set_kv ROS_ENABLED "${ROS_ENABLED_VAL}"
[ -n "${MAVLINK_ENABLED_VAL:-}" ] && set_kv MAVLINK_ENABLED "${MAVLINK_ENABLED_VAL}"
[ -n "${CAMERA_SUPPORT_VAL:-}" ] && set_kv CAMERA_SUPPORT "${CAMERA_SUPPORT_VAL}"
[ -n "${OPENCR_SUPPORT_VAL:-}" ] && set_kv OPENCR_SUPPORT "${OPENCR_SUPPORT_VAL}"
# WiFi settings
[ -n "${WIFI_SSID_0_VAL:-}" ] && set_kv WIFI_SSID_0 "${WIFI_SSID_0_VAL}"
[ -n "${WIFI_PASS_0_VAL:-}" ] && set_kv WIFI_PASS_0 "${WIFI_PASS_0_VAL}"
[ -n "${WIFI_SSID_1_VAL:-}" ] && set_kv WIFI_SSID_1 "${WIFI_SSID_1_VAL}"
[ -n "${WIFI_PASS_1_VAL:-}" ] && set_kv WIFI_PASS_1 "${WIFI_PASS_1_VAL}"
[ -n "${WIFI_SSID_2_VAL:-}" ] && set_kv WIFI_SSID_2 "${WIFI_SSID_2_VAL}"
[ -n "${WIFI_PASS_2_VAL:-}" ] && set_kv WIFI_PASS_2 "${WIFI_PASS_2_VAL}"

# log the generated conf location
echo "Generated ${LOCAL_CONF} (profile=${PROFILE})"

# show a short preview if dry-run
if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "--- preview ${LOCAL_CONF} ---"
  sed -n '1,240p' "${LOCAL_CONF}"
  exit 0
fi

# helper to read a key from local.conf (simple parser)
get_kv() {
  key="$1"
  if grep -q "^${key}" "${LOCAL_CONF}"; then
    grep "^${key}" "${LOCAL_CONF}" | head -n1 | sed -E 's/^[^=]+= *"(.*)"/\1/'
  else
    echo ""
  fi
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

  mask() {
    v="$1"
    if [[ -z "$v" ]]; then
      echo ""
    else
      echo "${v:0:4}***"
    fi
  }

  # For each generated image, copy artifacts into OUTPUT_ROOT/<image_name_or_basename>/
  IMAGES=$(find . -path "*/tmp/deploy/images/*/*.{wic,img,zip}" -type f -mmin -120 -print 2>/dev/null || true)
  if [[ -z "${IMAGES}" ]]; then
    # no images found; still write a summary into OUTPUT_ROOT/_no_image_
    target_dir="${OUTPUT_ROOT}/_no_image_"
    mkdir -p "${target_dir}"
    OUTFILE="${target_dir}/image-parameter_summary"
  else
    OUTFILE=""
  fi

  # process images and create per-image output dirs
  if [[ -n "${IMAGES}" ]]; then
    while IFS= read -r img; do
      img_dir=$(dirname "${img}")
      bn=$(basename "${img}")
      base_noext="${bn%.*}"
      # determine target dir name from IMAGE_NAME_VAL if present, else base filename
      if [[ -n "${IMAGE_NAME_VAL}" ]]; then
        dir_name="${IMAGE_NAME_VAL}"
      else
        dir_name="${base_noext}"
      fi
      target_dir="${OUTPUT_ROOT}/${dir_name}"
      mkdir -p "${target_dir}"

      # copy the main image as 'image' (strip extension)
      cp -f "${img}" "${target_dir}/image"

      # Copy related auxiliary files with same base name (e.g., .wic.bmap, .bmap)
      for aux in "${img_dir}/${base_noext}"*; do
        if [[ -f "${aux}" && "${aux}" != "${img}" ]]; then
          cp -f "${aux}" "${target_dir}/$(basename "${aux}")"
        fi
      done

      # write parameter summary file inside target dir
      OUTFILE="${target_dir}/image-parameter_summary"
      {
        echo "timestamp: ${TS}"
        echo "profile: ${PROFILE}"
        echo "machine: ${MACHINE_VAL:-${MACHINE}}"
        echo "image_name: ${IMAGE_NAME_VAL}"
        echo "robot_type: ${ROBOT_TYPE_VAL}"
        echo "robot_user: ${ROBOT_USER_VAL}"
        echo "robot_pass: $(mask "${ROBOT_PASS_VAL}")"
        echo "hostname_prefix: ${HOSTNAME_PREFIX_VAL}"
        echo "tailscale_enabled: ${TAILSCALE_ENABLED_VAL}"
        echo "ros_enabled: ${ROS_ENABLED_VAL}"
        echo "mavlink_enabled: ${MAVLINK_ENABLED_VAL}"
        echo "camera_support: ${CAMERA_SUPPORT_VAL}"
        echo "opencr_support: ${OPENCR_SUPPORT_VAL}"
        echo "kas_command: kas build configs/kas/${PROFILE}.yml"
        echo "git_hash: ${GIT_HASH}"

        # list generated images related to this base
        printf "\nfound_images:\n"
        find "${img_dir}" -maxdepth 1 -type f -name "${base_noext}*" -print || true
      } > "${OUTFILE}"

      echo "Created package: ${target_dir}/ (image + artifacts + image-parameter_summary)"
    done <<< "${IMAGES}"
  else
    # write a minimal summary when no images were created
    {
      echo "timestamp: ${TS}"
      echo "profile: ${PROFILE}"
      echo "machine: ${MACHINE_VAL:-${MACHINE}}"
      echo "image_name: ${IMAGE_NAME_VAL}"
      echo "robot_type: ${ROBOT_TYPE_VAL}"
      echo "robot_user: ${ROBOT_USER_VAL}"
      echo "robot_pass: $(mask "${ROBOT_PASS_VAL}")"
      echo "hostname_prefix: ${HOSTNAME_PREFIX_VAL}"
      echo "tailscale_enabled: ${TAILSCALE_ENABLED_VAL}"
      echo "ros_enabled: ${ROS_ENABLED_VAL}"
      echo "mavlink_enabled: ${MAVLINK_ENABLED_VAL}"
      echo "camera_support: ${CAMERA_SUPPORT_VAL}"
      echo "opencr_support: ${OPENCR_SUPPORT_VAL}"
      echo "kas_command: kas build configs/kas/${PROFILE}.yml"
      echo "git_hash: ${GIT_HASH}"
      printf "\nfound_images:\n"
    } > "${OUTFILE}"
    echo "Wrote build summary to ${OUTFILE}"
  fi
}

# run kas build unless NO_BUILD
KAS_CMD=(kas build "configs/kas/${PROFILE}.yml")
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
