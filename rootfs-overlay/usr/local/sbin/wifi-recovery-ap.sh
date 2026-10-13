#!/usr/bin/env bash
# /usr/local/sbin/wifi-recovery-ap.sh
# If station Wi-Fi is not connected, bring up a local recovery AP so SSH and
# the One-KVM Web UI remain reachable. Never logs the PSK.
set -Eeuo pipefail

[[ -f /etc/default/one-kvm-recovery-ap ]] && . /etc/default/one-kvm-recovery-ap

SSID="${RECOVERY_AP_SSID:-taishankvm-recovery}"
PSK="${RECOVERY_AP_PSK:-}"
ADDR="${RECOVERY_AP_ADDRESS:-192.168.66.1/24}"
IFACE="${RECOVERY_AP_IFACE:-wlan0}"
CON_NAME="one-kvm-recovery"

log() { logger -t one-kvm-recovery-ap -- "$*" 2>/dev/null || printf '%s\n' "$*"; }

if [[ -z "${PSK}" ]]; then
  log "RECOVERY_AP_PSK is not configured; refusing to start an open AP"
  exit 1
fi

if nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q '^wifi:connected'; then
  log "station Wi-Fi is connected; recovery AP not needed"
  exit 0
fi

log "station Wi-Fi unavailable; bringing up recovery AP ${SSID} on ${IFACE}"
nmcli connection delete "${CON_NAME}" >/dev/null 2>&1 || true
nmcli connection add type wifi ifname "${IFACE}" con-name "${CON_NAME}" autoconnect no ssid "${SSID}" >/dev/null
nmcli connection modify "${CON_NAME}" \
  802-11-wireless.mode ap \
  802-11-wireless.band bg \
  ipv4.method shared \
  ipv4.addresses "${ADDR}" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "${PSK}" >/dev/null
nmcli connection up "${CON_NAME}" >/dev/null
log "recovery AP active at ${ADDR%/*}"
