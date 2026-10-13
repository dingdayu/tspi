#!/usr/bin/env bash
# scripts/rootfs/install-one-kvm.sh
# Install the pinned native One-KVM (Rust) ARM64 .deb into an unpacked target
# rootfs and enable its service. The .deb is cached under downloads/.
#   ROOTFS_DIR  target rootfs (required)
# No Docker is installed on the target.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
load_env

LOG_FILE="${LOGS_DIR}/one-kvm-install.log"

fetch_deb() {
  local deb_name="$1" dest="$2"
  if [[ -s "${dest}" ]]; then
    log_info "using cached ${deb_name}"
    return 0
  fi
  require_cmd curl
  local url="${ONE_KVM_DEB_URL:-}"
  [[ -n "${url}" ]] || die "ONE_KVM_DEB_URL is not set in config/versions.env"
  log_info "downloading ${deb_name}"
  if ! curl -fL --retry 3 -o "${dest}.part" "${url}"; then
    if [[ -n "${ONE_KVM_DEB_URL_MIRROR:-}" ]]; then
      log_warn "primary download failed; trying mirror"
      curl -fL --retry 3 -o "${dest}.part" "${ONE_KVM_DEB_URL_MIRROR}" || { rm -f "${dest}.part"; die "One-KVM download failed from both primary and mirror"; }
    else
      rm -f "${dest}.part"
      die "One-KVM download failed: ${url}"
    fi
  fi
  mv "${dest}.part" "${dest}"
}

verify_sha() {
  local deb="$1"
  if [[ -n "${ONE_KVM_SHA256:-}" ]]; then
    local got
    got="$(sha256sum "${deb}" | awk '{print $1}')"
    [[ "${got}" == "${ONE_KVM_SHA256}" ]] || die "One-KVM SHA256 mismatch: want ${ONE_KVM_SHA256}, got ${got}"
    log_info "One-KVM SHA256 verified"
  else
    log_warn "ONE_KVM_SHA256 is empty; recording the computed hash for pinning"
    log_info "computed sha256: $(sha256sum "${deb}" | awk '{print $1}')"
  fi
}

enable_service() {
  local rootfs="$1"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --root="${rootfs}" enable "${ONE_KVM_SERVICE:-one-kvm.service}" \
      && log_info "enabled ${ONE_KVM_SERVICE:-one-kvm.service}" \
      || log_warn "systemctl --root enable failed; verify the unit after first boot"
  else
    local unit="${ONE_KVM_SERVICE:-one-kvm.service}"
    mkdir -p "${rootfs}/etc/systemd/system/multi-user.target.wants"
    ln -sf "/lib/systemd/system/${unit}" "${rootfs}/etc/systemd/system/multi-user.target.wants/${unit}"
    log_info "created enable symlink for ${unit}"
  fi
}

install_main() {
  log_phase "Installing One-KVM ${ONE_KVM_VERSION:-unknown}"
  ensure_build_dirs
  require_cmd bash dpkg-deb
  [[ -n "${ROOTFS_DIR:-}" && -d "${ROOTFS_DIR}" ]] || die "ROOTFS_DIR must point to an unpacked target rootfs"

  local deb="${DOWNLOADS_DIR}/${ONE_KVM_DEB:-one-kvm_arm64.deb}"
  mkdir -p "${DOWNLOADS_DIR}"
  fetch_deb "${ONE_KVM_DEB:-one-kvm_arm64.deb}" "${deb}" 2>&1 | tee -a "${LOG_FILE}"
  verify_sha "${deb}" 2>&1 | tee -a "${LOG_FILE}"

  log_info "extracting .deb into ${ROOTFS_DIR}"
  dpkg-deb --extract "${deb}" "${ROOTFS_DIR}" || die "failed to extract ${deb}"

  [[ -f "${ROOTFS_DIR}${ONE_KVM_BIN:-/usr/bin/one-kvm}" ]] \
    && log_info "installed binary: ${ONE_KVM_BIN:-/usr/bin/one-kvm}" \
    || log_warn "expected binary ${ONE_KVM_BIN:-/usr/bin/one-kvm} not found after extraction"

  mkdir -p "${ROOTFS_DIR}${ONE_KVM_DATA_DIR:-/etc/one-kvm}"
  enable_service "${ROOTFS_DIR}"

  if [[ -e "${ROOTFS_DIR}/usr/bin/docker" || -e "${ROOTFS_DIR}/usr/bin/containerd" ]]; then
    die "a container runtime appeared in the target rootfs; One-KVM must be native only"
  fi
  log_info "One-KVM install complete; log: ${LOG_FILE#${PROJECT_ROOT}/}"
}

install_main
