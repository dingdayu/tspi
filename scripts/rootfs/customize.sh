#!/usr/bin/env bash
# scripts/rootfs/customize.sh
# Turn a vendor Debian rootfs into the TaishanPi One-KVM appliance:
# packages, overlay, account, SSH, Wi-Fi preset, mDNS, journald limits,
# ADB-gadget masking, and native One-KVM install.
#   ROOTFS_DIR  unpacked target rootfs (required)
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
load_env

[[ -n "${ROOTFS_DIR:-}" && -d "${ROOTFS_DIR}" ]] || die "ROOTFS_DIR must point to an unpacked target rootfs"

TARGET_USERNAME="${TARGET_USERNAME:-kvm}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-taishankvm}"
TARGET_MDNS_NAME="${TARGET_MDNS_NAME:-taishankvm.local}"
ENABLE_RECOVERY_AP="${ENABLE_RECOVERY_AP:-1}"
ALLOW_PASSWORD_SSH="${ALLOW_PASSWORD_SSH:-0}"
ENABLE_ADB_DEBUG="${ENABLE_ADB_DEBUG:-0}"

CHROOT_MOUNTS=()

chroot_setup() {
  if [[ ! -e "${ROOTFS_DIR}/usr/bin/qemu-aarch64-static" ]] && [[ -e /usr/bin/qemu-aarch64-static ]]; then
    cp /usr/bin/qemu-aarch64-static "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || true
  fi
  for m in dev proc sys; do
    mkdir -p "${ROOTFS_DIR}/${m}"
    if ! mountpoint -q "${ROOTFS_DIR}/${m}"; then
      mount --bind "/${m}" "${ROOTFS_DIR}/${m}" && CHROOT_MOUNTS+=("${ROOTFS_DIR}/${m}") || log_warn "could not bind /${m} into rootfs"
    fi
  done
}
chroot_teardown() {
  local m
  for m in "${CHROOT_MOUNTS[@]:-}"; do umount "${m}" 2>/dev/null || true; done
}
trap chroot_teardown EXIT

apply_overlay() {
  log_phase "Applying rootfs-overlay/"
  require_cmd rsync
  rsync -aHAX "${OVERLAY_DIR}/" "${ROOTFS_DIR}/"
  chmod 0755 "${ROOTFS_DIR}/usr/local/sbin/"*.sh 2>/dev/null || true
  log_info "overlay applied"
}

install_packages() {
  log_phase "Installing target packages"
  [[ -f "${CONFIG_DIR}/packages-target.txt" ]] || die "missing config/packages-target.txt"
  local -a pkgs=()
  local line
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "${line}" | tr -d '[:space:]')"
    [[ -n "${line}" ]] && pkgs+=("${line}")
  done <"${CONFIG_DIR}/packages-target.txt"
  [[ ${#pkgs[@]} -gt 0 ]] || die "no packages parsed from packages-target.txt"
  if chroot "${ROOTFS_DIR}" /bin/sh -c 'command -v apt-get >/dev/null 2>&1'; then
    if ! chroot "${ROOTFS_DIR}" /bin/sh -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${pkgs[*]}"; then
      log_warn "apt install reported errors; verify the package list against the SDK archive"
    fi
  else
    log_warn "apt-get not available in rootfs; skipping package install (add packages via the vendor rootfs step)"
  fi
}

# Append a user to a group's member list in /etc/group (host-side text edit, so
# it works regardless of chroot/gpasswd availability and never duplicates).
add_user_to_group() {
  local grp="$1" usr="$2"
  awk -F: -v OFS=: -v g="${grp}" -v u="${usr}" '
    $1==g {
      if ($4=="") { $4=u }
      else if (index(","$4",", ","u",")==0) { $4=$4 "," u }
    }
    { print }
  ' "${ROOTFS_DIR}/etc/group" >"${ROOTFS_DIR}/etc/group.tmp" && \
    mv "${ROOTFS_DIR}/etc/group.tmp" "${ROOTFS_DIR}/etc/group"
}

create_user() {
  log_phase "Creating maintenance account ${TARGET_USERNAME}"
  local group_file="${ROOTFS_DIR}/etc/group"
  local passwd_file="${ROOTFS_DIR}/etc/passwd"
  local shadow_file="${ROOTFS_DIR}/etc/shadow"

  # Collapse duplicate group entries for the target name (an earlier fallback
  # may have appended a second one), keeping the first.
  awk -F: -v OFS=: -v g="${TARGET_USERNAME}" '
    $1==g { n++; if (n>1) next } { print }
  ' "${group_file}" >"${group_file}.tmp" && mv "${group_file}.tmp" "${group_file}"

  # Reuse a pre-existing group with the target name as the primary group.
  local gid groups="" g
  gid="$(awk -F: -v g="${TARGET_USERNAME}" '$1==g { print $3; exit }' "${group_file}")"
  for g in sudo video input plugdev audio; do
    grep -q "^${g}:" "${group_file}" && groups="${groups:+${groups},}${g}"
  done

  if grep -q "^${TARGET_USERNAME}:" "${passwd_file}" 2>/dev/null; then
    log_info "user already exists"
    if [[ -n "${gid}" ]]; then
      awk -F: -v OFS=: -v u="${TARGET_USERNAME}" -v g="${gid}" \
        '$1==u { $4=g } { print }' "${passwd_file}" >"${passwd_file}.tmp" && \
        mv "${passwd_file}.tmp" "${passwd_file}"
    fi
  else
    local -a args=(-m -s /bin/bash)
    [[ -n "${gid}" ]] && args+=(-g "${gid}")
    [[ -n "${groups}" ]] && args+=(-G "${groups}")
    if chroot "${ROOTFS_DIR}" useradd "${args[@]}" "${TARGET_USERNAME}"; then
      log_info "created ${TARGET_USERNAME} via useradd${groups:+ (groups: ${groups})}"
    else
      log_warn "useradd failed; creating ${TARGET_USERNAME} directly in /etc/{passwd,shadow,group}"
      local uid
      uid="$(awk -F: '$3>=1000 && $3<60000 {print $3}' "${passwd_file}" | sort -n | tail -1)"
      uid="${uid:-1000}"; uid=$((uid + 1))
      if [[ -z "${gid}" ]]; then
        gid="${uid}"
        printf '%s:x:%s:\n' "${TARGET_USERNAME}" "${gid}" >>"${group_file}"
      fi
      printf '%s:x:%s:%s::/home/%s:/bin/bash\n' \
        "${TARGET_USERNAME}" "${uid}" "${gid}" "${TARGET_USERNAME}" >>"${passwd_file}"
      printf '%s:!:19000:0:99999:7:::\n' "${TARGET_USERNAME}" >>"${shadow_file}"
      mkdir -p "${ROOTFS_DIR}/home/${TARGET_USERNAME}"
      if [[ -d "${ROOTFS_DIR}/etc/skel" ]]; then
        cp -a "${ROOTFS_DIR}/etc/skel/." "${ROOTFS_DIR}/home/${TARGET_USERNAME}/" 2>/dev/null || true
      fi
      log_info "created ${TARGET_USERNAME} (uid ${uid}, gid ${gid})"
    fi
  fi

  # Supplementary group membership directly in /etc/group.
  for g in sudo video input plugdev audio; do
    grep -q "^${g}:" "${group_file}" || continue
    add_user_to_group "${g}" "${TARGET_USERNAME}"
  done

  # Align home ownership with the account's uid:gid.
  local puid pgid
  puid="$(awk -F: -v u="${TARGET_USERNAME}" '$1==u { print $3; exit }' "${passwd_file}")"
  pgid="$(awk -F: -v u="${TARGET_USERNAME}" '$1==u { print $4; exit }' "${passwd_file}")"
  if [[ -n "${puid}" && -n "${pgid}" && -d "${ROOTFS_DIR}/home/${TARGET_USERNAME}" ]]; then
    chown -R "${puid}:${pgid}" "${ROOTFS_DIR}/home/${TARGET_USERNAME}"
  fi

  chroot "${ROOTFS_DIR}" passwd -l "${TARGET_USERNAME}" >/dev/null 2>&1 || true
}

configure_ssh() {
  log_phase "Configuring SSH"
  local auth_dir="${ROOTFS_DIR}/home/${TARGET_USERNAME}/.ssh"
  if [[ -n "${SSH_PUBLIC_KEY_FILE:-}" && -f "${SSH_PUBLIC_KEY_FILE}" ]]; then
    mkdir -p "${auth_dir}"
    cp "${SSH_PUBLIC_KEY_FILE}" "${auth_dir}/authorized_keys"
    chmod 0700 "${auth_dir}"; chmod 0600 "${auth_dir}/authorized_keys"
    chroot "${ROOTFS_DIR}" chown -R "${TARGET_USERNAME}:${TARGET_USERNAME}" "/home/${TARGET_USERNAME}/.ssh" 2>/dev/null || true
    log_info "installed authorized_keys for ${TARGET_USERNAME}"
  else
    log_warn "no SSH public key provided; enabling password auth as a fallback"
    ALLOW_PASSWORD_SSH=1
  fi
  local sshd_conf="${ROOTFS_DIR}/etc/ssh/sshd_config.d/10-appliance.conf"
  if [[ "${ALLOW_PASSWORD_SSH}" == "1" ]]; then
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "${sshd_conf}" 2>/dev/null || true
    log_warn "password SSH is ENABLED (development mode)"
  fi
  chroot "${ROOTFS_DIR}" systemctl enable ssh 2>/dev/null || true
}

configure_wifi() {
  log_phase "Configuring station Wi-Fi"
  if [[ -z "${WIFI_SSID:-}" || -z "${WIFI_PSK:-}" ]]; then
    log_warn "WIFI_SSID/WIFI_PSK not set; skipping Wi-Fi profile (image will need manual provisioning)"
    return 0
  fi
  local dir="${ROOTFS_DIR}/etc/NetworkManager/system-connections"
  mkdir -p "${dir}"
  local safe_ssid="${WIFI_SSID//[^A-Za-z0-9_.-]/_}"
  local prof="${dir}/${safe_ssid}.nmconnection"
  umask 077
  cat >"${prof}" <<EOF
[connection]
id=${WIFI_SSID}
type=wifi
interface-name=wlan0
autoconnect=true
autoconnect-priority=100

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PSK}

[ipv4]
method=auto
EOF
  chmod 0600 "${prof}"
  log_info "wrote Wi-Fi profile for SSID '${WIFI_SSID}' (psk not logged)"
}

configure_hostname_mdns() {
  log_phase "Hostname and mDNS"
  printf '%s\n' "${TARGET_HOSTNAME}" >"${ROOTFS_DIR}/etc/hostname"
  if ! grep -q "${TARGET_HOSTNAME}" "${ROOTFS_DIR}/etc/hosts" 2>/dev/null; then
    printf '127.0.1.1\t%s\n' "${TARGET_HOSTNAME}" >>"${ROOTFS_DIR}/etc/hosts"
  fi
  chroot "${ROOTFS_DIR}" systemctl enable avahi-daemon 2>/dev/null || true
}

configure_recovery_ap() {
  [[ "${ENABLE_RECOVERY_AP}" == "1" ]] || { log_info "recovery AP disabled"; return 0; }
  if [[ -z "${RECOVERY_AP_PSK:-}" ]]; then
    log_warn "ENABLE_RECOVERY_AP=1 but RECOVERY_AP_PSK is empty; recovery AP will refuse to start"
    return 0
  fi
  log_phase "Configuring recovery AP defaults"
  local defaults="${ROOTFS_DIR}/etc/default/one-kvm-recovery-ap"
  mkdir -p "$(dirname "${defaults}")"
  umask 077
  cat >"${defaults}" <<EOF
RECOVERY_AP_SSID=${RECOVERY_AP_SSID:-taishankvm-recovery}
RECOVERY_AP_PSK=${RECOVERY_AP_PSK}
RECOVERY_AP_ADDRESS=${RECOVERY_AP_ADDRESS:-192.168.66.1/24}
RECOVERY_AP_IFACE=wlan0
EOF
  chmod 0600 "${defaults}"
  log_info "wrote recovery AP defaults (psk not logged)"
}

enable_services() {
  log_phase "Enabling services"
  chroot "${ROOTFS_DIR}" systemctl enable NetworkManager 2>/dev/null || log_warn "could not enable NetworkManager"
  chroot "${ROOTFS_DIR}" systemctl enable systemd-timesyncd 2>/dev/null || true
  if [[ "${ENABLE_RECOVERY_AP}" == "1" ]]; then
    chroot "${ROOTFS_DIR}" systemctl enable one-kvm-recovery-ap.timer 2>/dev/null || log_warn "could not enable recovery-AP timer"
  fi
}

mask_adb() {
  log_phase "Disabling/masking vendor ADB gadget"
  chroot "${ROOTFS_DIR}" systemctl mask adbd.service 2>/dev/null || {
    mkdir -p "${ROOTFS_DIR}/etc/systemd/system"
    ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/adbd.service"
  }
  local cand
  for cand in usbdevice.service usb-gadget.service rockchip-adbd.service; do
    if [[ -e "${ROOTFS_DIR}/lib/systemd/system/${cand}" || -e "${ROOTFS_DIR}/etc/systemd/system/${cand}" ]]; then
      chroot "${ROOTFS_DIR}" systemctl mask "${cand}" 2>/dev/null || ln -sf /dev/null "${ROOTFS_DIR}/etc/systemd/system/${cand}"
      log_info "masked ${cand}"
    fi
  done
  log_info "ADB gadget masked (One-KVM owns the UDC in normal mode)"
}

customize_main() {
  log_phase "Rootfs customization"
  ensure_build_dirs
  require_cmd bash
  chroot_setup
  install_packages
  apply_overlay
  create_user
  configure_ssh
  configure_wifi
  configure_recovery_ap
  configure_hostname_mdns
  enable_services
  mask_adb
  log_phase "Installing One-KVM"
  ROOTFS_DIR="${ROOTFS_DIR}" bash "${SCRIPTS_DIR}/rootfs/install-one-kvm.sh"
  log_info "customization complete"
}

customize_main
