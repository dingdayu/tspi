#!/usr/bin/env bash
# scripts/verify/target-smoke.sh
# Read-only smoke test to run ON a booted TaishanPi (copy this file over and
# run with sudo). Makes no destructive changes. Prints a categorized verdict.
set -u

pass=0; warn=0; fail=0
ok()   { printf '  [ OK ] %s\n' "$*"; pass=$((pass + 1)); }
note() { printf '  [WARN] %s\n' "$*"; warn=$((warn + 1)); }
bad()  { printf '  [FAIL] %s\n' "$*"; fail=$((fail + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

section() { printf '\n== %s ==\n' "$*"; }

section "Kernel"
uname -a
if [[ -d /sys/class/udc ]] && [[ -n "$(ls -A /sys/class/udc 2>/dev/null)" ]]; then
  ok "UDC present: $(ls /sys/class/udc | tr '\n' ' ')"
else
  bad "no UDC in /sys/class/udc (DWC3 not in peripheral mode or driver missing)"
fi
if mount 2>/dev/null | grep -q configfs; then
  ok "configfs mounted"
else
  bad "configfs not mounted (needed for USB gadget)"
fi
if [[ -d /sys/kernel/config/usb_gadget ]]; then
  ok "usb_gadget configfs present: $(ls /sys/kernel/config/usb_gadget 2>/dev/null | tr '\n' ' ')"
else
  bad "/sys/kernel/config/usb_gadget missing"
fi
if [[ -d /sys/module/libcomposite ]]; then ok "libcomposite loaded"; else note "libcomposite not loaded (one-kvm should load it)"; fi

section "SSH"
if systemctl is-enabled ssh >/dev/null 2>&1; then ok "ssh enabled at boot"; else bad "ssh not enabled"; fi
if systemctl is-active ssh >/dev/null 2>&1; then ok "ssh active"; else bad "ssh not active"; fi

section "Network"
if systemctl is-active NetworkManager >/dev/null 2>&1; then ok "NetworkManager active"; else bad "NetworkManager not active"; fi
if ip link show wlan0 >/dev/null 2>&1; then ok "wlan0 present"; else bad "wlan0 missing (AP6212)"; fi
if have nmcli; then nmcli -t device status 2>/dev/null || note "nmcli device status failed"; else note "nmcli not installed"; fi
ip -brief addr show 2>/dev/null || true

section "One-KVM"
if systemctl is-enabled one-kvm >/dev/null 2>&1; then ok "one-kvm enabled"; else bad "one-kvm not enabled"; fi
if systemctl is-active one-kvm >/dev/null 2>&1; then ok "one-kvm active"; else bad "one-kvm not active"; fi
systemctl status one-kvm --no-pager -l 2>/dev/null | head -12 || true
journalctl -u one-kvm -n 30 --no-pager 2>/dev/null || note "no one-kvm journal entries"

section "ADB / gadget ownership"
if lsmod 2>/dev/null | grep -q '^g_'; then
  note "a legacy g_* gadget module is bound; verify it is not contending with one-kvm for the UDC"
else
  ok "no legacy g_* gadget module loaded"
fi
if systemctl is-active adbd >/dev/null 2>&1; then bad "adbd is active (must be disabled in normal mode)"; else ok "adbd not active"; fi

section "Video capture (UVC)"
if have lsusb; then lsusb | grep -iE 'cam|video|uvc|2109|2130' || note "no obvious UVC device in lsusb"; else note "lsusb not installed"; fi
if have v4l2-ctl; then v4l2-ctl --list-devices 2>/dev/null || note "v4l2-ctl found no devices"; else note "v4l2-ctl not installed"; fi
ls -l /dev/video* 2>/dev/null || note "no /dev/video* nodes"

section "Verdict"
printf 'pass=%d warn=%d fail=%d\n' "$pass" "$warn" "$fail"
if [[ "${fail}" -gt 0 ]]; then
  printf 'RESULT: FAIL (see [FAIL] items above)\n'
  exit 1
fi
printf 'RESULT: PASS (warnings may need review)\n'
