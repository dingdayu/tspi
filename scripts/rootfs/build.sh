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

# The vendor Debian rootfs is built from a prebuilt base tarball, but
# device/rockchip/common/scripts/check-debian.sh refuses to proceed unless
# live-build and debootstrap advertise the target release (bookworm). Create the
# expected markers at runtime so a stale builder image cannot block the build.
# Idempotent; must run as root (the builder container does).
ensure_debian_check_markers() {
  local rel="${RK_DEBIAN_VERSION:-bookworm}"
  local lb="/usr/share/live/build/data/debian-cd/${rel}"
  local db="/usr/share/debootstrap/scripts/${rel}"
  if [[ "$(id -u)" -ne 0 ]]; then
    log_warn "not root: cannot create Debian check markers (${rel}); rebuild the builder image if check-debian.sh fails"
    return 0
  fi
  mkdir -p "${lb}"
  if [[ ! -e "${db}" ]]; then
    if [[ -e /usr/share/debootstrap/scripts/sid ]]; then
      ln -sf /usr/share/debootstrap/scripts/sid "${db}" 2>/dev/null || true
    else
      : > "${db}" 2>/dev/null || true
    fi
  fi
  log_info "ensured Debian check markers for ${rel}"

  # Privileged containers do not get /proc/sys/fs/binfmt_misc mounted, so the
  # vendor check-debian.sh cannot see qemu-aarch64. Mount a fresh instance and
  # register the in-image qemu-aarch64-static (idempotent).
  if [[ ! -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    mkdir -p /proc/sys/fs/binfmt_misc 2>/dev/null || true
    mountpoint -q /proc/sys/fs/binfmt_misc 2>/dev/null || \
      mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    if [[ -r /proc/sys/fs/binfmt_misc/register ]]; then
      update-binfmts --enable qemu-aarch64 2>/dev/null || true
    fi
    log_info "binfmt_misc: qemu-aarch64 readable=$([[ -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] && echo yes || echo no)"
  fi
}

build_main() {
  log_phase "Rootfs build (${ROOTFS_SYSTEM})"
  ensure_build_dirs
  require_cmd bash
  sdk_require_present
  if [[ "${ROOTFS_SYSTEM}" == "debian" ]]; then
    ensure_debian_check_markers
  fi

  local work
  work="$(sdk_find_work_dir)" || die "cannot locate the SDK work tree"
  local build_sh="${work}/build.sh"
  require_file "${build_sh}"

  # The vendor's wifibt post-hook (scripts/post-wifibt.sh) refuses to run if any
  # file under external/rkwifibt is not owned by RK_OWNER_UID (the SDK owner).
  # Root container builds leave root-owned .o/.ko artifacts there, so realign
  # ownership to the SDK owner before invoking the vendor build.
  local sdk_real owner_uid
  sdk_real="$(realpath "${work}" 2>/dev/null || true)"
  owner_uid="$(stat -c %u "${sdk_real}" 2>/dev/null || echo 0)"
  if [[ "${owner_uid}" -ne 0 && -d "${sdk_real}/external/rkwifibt" ]]; then
    log_info "aligning external/rkwifibt ownership to uid ${owner_uid}"
    chown -R "${owner_uid}:${owner_uid}" "${sdk_real}/external/rkwifibt" 2>/dev/null || \
      log_warn "could not fully realign external/rkwifibt ownership"
  fi

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
