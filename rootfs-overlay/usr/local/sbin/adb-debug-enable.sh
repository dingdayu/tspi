#!/usr/bin/env bash
# /usr/local/sbin/adb-debug-enable.sh
# Opt-in ADB debug mode. Mutually exclusive with One-KVM UDC ownership:
# stop One-KVM, release the gadget, then bind ADB.
# Requires ENABLE_ADB_DEBUG=1 (config/build.env or /etc/default/one-kvm-adb).
set -Eeuo pipefail

[[ -f /etc/default/one-kvm-adb ]] && . /etc/default/one-kvm-adb
[[ "${ENABLE_ADB_DEBUG:-0}" == "1" ]] || { echo "ADB debug is disabled (set ENABLE_ADB_DEBUG=1)" >&2; exit 1; }

LOCK=/run/one-kvm-adb.lock
exec 9>"${LOCK}" || exit 1
flock -n 9 || { echo "another ADB/One-KVM transition is in progress" >&2; exit 1; }

echo "Stopping One-KVM"
systemctl stop one-kvm.service 2>/dev/null || true

echo "Releasing USB gadget (UDC)"
for udc in /sys/kernel/config/usb_gadget/*/UDC; do
  [[ -e "${udc}" ]] || continue
  echo "" >"${udc}" 2>/dev/null || true
done
for g in /sys/kernel/config/usb_gadget/*; do
  [[ -d "${g}" ]] || continue
  rmdir "${g}/configs/"*/ 2>/dev/null || true
  rmdir "${g}/functions/"*/ 2>/dev/null || true
  rmdir "${g}" 2>/dev/null || true
done

echo "Enabling ADB"
systemctl unmask adbd.service 2>/dev/null || true
systemctl start adbd.service 2>/dev/null || systemctl start adb.service 2>/dev/null || {
  echo "no adbd/adb unit found; vendor ADB tooling may differ" >&2; exit 1;
}
echo "ADB debug mode enabled (One-KVM stopped)."
