#!/usr/bin/env bash
# /usr/local/sbin/one-kvm-udev-setup.sh
# Ensure stable permissions for the UVC capture device and load the USB gadget
# module. Idempotent; safe to run multiple times.
set -Eeuo pipefail

RULES=/etc/udev/rules.d/70-one-kvm.rules

modprobe libcomposite 2>/dev/null || true

cat >"${RULES}" <<'EOF'
# One-KVM: video capture devices accessible to the video group.
SUBSYSTEM=="video4linux", GROUP="video", MODE="0660"
# One-KVM: configfs gadget is managed by the One-KVM service as root.
SUBSYSTEM=="usb", ATTR{idVendor}=="1d6b", MODE="0660"
EOF

if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules 2>/dev/null || true
  udevadm trigger 2>/dev/null || true
fi
echo "one-kvm udev rules installed at ${RULES}"
