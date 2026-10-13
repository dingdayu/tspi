#!/usr/bin/env bash
# /usr/local/sbin/adb-debug-disable.sh
# Reverse of adb-debug-enable.sh: stop/unmask ADB, re-mask it, and hand UDC
# ownership back to One-KVM.
set -Eeuo pipefail

LOCK=/run/one-kvm-adb.lock
exec 9>"${LOCK}" || exit 1
flock -n 9 || { echo "another ADB/One-KVM transition is in progress" >&2; exit 1; }

echo "Stopping ADB"
systemctl stop adbd.service 2>/dev/null || systemctl stop adb.service 2>/dev/null || true
systemctl disable adbd.service 2>/dev/null || true
systemctl mask adbd.service 2>/dev/null || ln -sf /dev/null /etc/systemd/system/adbd.service

echo "Releasing any ADB gadget"
for udc in /sys/kernel/config/usb_gadget/*/UDC; do
  [[ -e "${udc}" ]] || continue
  echo "" >"${udc}" 2>/dev/null || true
done

echo "Restarting One-KVM (reclaims the UDC)"
systemctl start one-kvm.service 2>/dev/null || true
echo "ADB debug mode disabled; One-KVM owns the UDC again."
