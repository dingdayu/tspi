#!/usr/bin/env bash
# scripts/rootfs/verify.sh
# Inspect an unpacked target rootfs and assert the appliance contract.
#   ROOTFS_DIR  target rootfs (default: build/rootfs)
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
load_env

ROOTFS_DIR="${ROOTFS_DIR:-${BUILD_DIR}/rootfs}"
failures=0
fail() { log_error "$*"; failures=$((failures + 1)); }
ok() { log_info "OK   $*"; }

pkg_installed() { [[ -e "$1" ]]; }
svc_enabled() { [[ -L "$1" || -f "$1" ]]; }

verify_main() {
  log_phase "Rootfs verification"
  [[ -d "${ROOTFS_DIR}" ]] || die "rootfs not found at ${ROOTFS_DIR}; build it first (make rootfs)"

  if [[ -e "${ROOTFS_DIR}/usr/sbin/sshd" || -e "${ROOTFS_DIR}/usr/sbin/sshd.core" ]]; then
    ok "openssh-server present"
  else
    fail "openssh-server missing"
  fi
  if svc_enabled "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/ssh.service"; then
    ok "ssh enabled at boot"
  else
    fail "ssh.service not enabled"
  fi

  if [[ -e "${ROOTFS_DIR}/usr/bin/NetworkManager" || -e "${ROOTFS_DIR}/usr/sbin/NetworkManager" ]]; then
    ok "NetworkManager present"
  else
    fail "NetworkManager missing"
  fi
  if svc_enabled "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/NetworkManager.service"; then
    ok "NetworkManager enabled"
  else
    fail "NetworkManager not enabled"
  fi

  local profile
  profile="$(find "${ROOTFS_DIR}/etc/NetworkManager/system-connections" -name '*.nmconnection' -print -quit 2>/dev/null || true)"
  if [[ -n "${profile}" ]]; then
    local mode
    mode="$(stat -c '%a' "${profile}")"
    [[ "${mode}" == "600" ]] && ok "wifi profile present and 0600" || fail "wifi profile ${profile#${ROOTFS_DIR}} has mode ${mode} (want 600)"
  else
    fail "no NetworkManager wifi profile found"
  fi

  if [[ -e "${ROOTFS_DIR}${ONE_KVM_BIN:-/usr/bin/one-kvm}" ]]; then
    ok "one-kvm binary present"
  else
    fail "one-kvm binary missing"
  fi
  if svc_enabled "${ROOTFS_DIR}/etc/systemd/system/multi-user.target.wants/${ONE_KVM_SERVICE:-one-kvm.service}"; then
    ok "one-kvm enabled at boot"
  else
    fail "one-kvm not enabled"
  fi

  if [[ "$(readlink "${ROOTFS_DIR}/etc/systemd/system/adbd.service" 2>/dev/null || true)" == "/dev/null" ]]; then
    ok "adbd masked"
  else
    log_warn "adbd.service not masked (confirm no vendor ADB gadget binds the UDC)"
  fi

  if grep -q '^libcomposite' "${ROOTFS_DIR}/etc/modules-load.d/one-kvm.conf" 2>/dev/null; then
    ok "libcomposite in modules-load.d"
  else
    fail "libcomposite not in modules-load.d"
  fi

  local bad
  for bad in usr/bin/docker usr/bin/dockerd usr/bin/containerd usr/bin/snapd usr/bin/cloud-init; do
    [[ -e "${ROOTFS_DIR}/${bad}" ]] && fail "forbidden package present: ${bad}"
  done

  [[ -e "${ROOTFS_DIR}/usr/bin/python3" ]] && ok "python3 present" || fail "python3 missing"

  if grep -q "^${TARGET_USERNAME:-kvm}:" "${ROOTFS_DIR}/etc/passwd" 2>/dev/null; then
    ok "target user ${TARGET_USERNAME:-kvm} exists"
  else
    fail "target user ${TARGET_USERNAME:-kvm} missing"
  fi
  if grep -qE "^sudo:.*\b${TARGET_USERNAME:-kvm}\b" "${ROOTFS_DIR}/etc/group" 2>/dev/null; then
    ok "target user in sudo group"
  else
    log_warn "target user not found in sudo group"
  fi

  log_phase "Summary"
  if [[ "${failures}" -gt 0 ]]; then
    die "rootfs verification FAILED (${failures})"
  fi
  log_info "rootfs verification: PASS"
}

verify_main
