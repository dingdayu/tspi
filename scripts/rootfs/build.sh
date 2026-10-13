#!/usr/bin/env bash
# scripts/rootfs/build.sh
# Build the vendor-supported Debian rootfs, unpack it to a directory, then
# hand off to customize.sh. The vendor entrypoint is detected, not assumed.
#   ROOTFS_SYSTEM=debian|buildroot|yocto   (default: debian)
#   ROOTFS_BUILD_CMD="..."                  full override
#   ROOTFS_DIR=/path                        skip unpacking, customize in place
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/rootfs-build.log"
ROOTFS_SYSTEM="${ROOTFS_SYSTEM:-debian}"
STAGE_DIR="${BUILD_DIR}/rootfs"

# Find a built rootfs image in the vendor output.
find_rootfs_image() {
  local w="$1"
  find "${w}/output" "${w}/debian" "${w}/ubuntu" "${w}/buildroot/output" \
    -maxdepth 5 -type f \( -name 'linaro-rootfs.img' -o -name 'rootfs.ext4' -o -name 'rootfs.img' -o -name 'ubuntu-jammy.img' \) \
    -print -quit 2>/dev/null || true
}

unpack_image() {
  local img="$1" out="$2"
  require_cmd rsync
  if [[ "$(id -u)" -ne 0 ]]; then
    die "unpacking ${img#${PROJECT_ROOT}/} requires root (mount loop). Enter the builder (make shell) and re-run."
  fi
  local mnt="${BUILD_DIR}/rootfs-mnt"
  mkdir -p "${mnt}" "${out}"
  log_info "mounting ${img#${PROJECT_ROOT}/} read-only to extract"
  mount -o loop,ro "${img}" "${mnt}" || die "failed to mount ${img}"
  rsync -aHAX --numeric-ids "${mnt}/" "${out}/" || { umount "${mnt}" || true; die "rsync from image failed"; }
  umount "${mnt}" || die "failed to unmount ${mnt}"
  rmdir "${mnt}" 2>/dev/null || true
}

build_main() {
  log_phase "Rootfs build (${ROOTFS_SYSTEM})"
  ensure_build_dirs
  require_cmd bash
  sdk_require_present

  local work
  work="$(sdk_find_work_dir)" || die "cannot locate the SDK work tree"
  local build_sh="${work}/build.sh"
  require_file "${build_sh}"

  if [[ -z "${ROOTFS_DIR:-}" ]]; then
    if [[ -n "${ROOTFS_BUILD_CMD:-}" ]]; then
      log_info "using ROOTFS_BUILD_CMD: ${ROOTFS_BUILD_CMD}"
      ( cd "${work}" && run_logged "${LOG_FILE}" bash -c "${ROOTFS_BUILD_CMD}" )
    else
      log_phase "vendor build.sh (RK_ROOTFS_SYSTEM=${ROOTFS_SYSTEM})"
      ( cd "${work}" && RK_ROOTFS_SYSTEM="${ROOTFS_SYSTEM}" run_logged "${LOG_FILE}" bash "${build_sh}" rootfs )
    fi

    local img
    img="$(find_rootfs_image "${work}")"
    if [[ -z "${img}" ]]; then
      die "no rootfs image found after the vendor build; set ROOTFS_DIR to an unpacked tree or ROOTFS_BUILD_CMD explicitly"
    fi
    log_info "rootfs image: ${img#${PROJECT_ROOT}/}"
    ROOTFS_DIR="${STAGE_DIR}"
    unpack_image "${img}" "${ROOTFS_DIR}"
  else
    log_info "using provided ROOTFS_DIR=${ROOTFS_DIR}"
  fi

  export ROOTFS_DIR
  bash "${SCRIPTS_DIR}/rootfs/customize.sh"
  log_info "rootfs build + customization complete; log: ${LOG_FILE#${PROJECT_ROOT}/}"
}

build_main
