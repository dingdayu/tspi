# Recovery

Ordered from least to most disruptive. UART is the last-resort console.

## 1. Network recovery (recovery AP)

If SSH or the One-KVM Web UI becomes unreachable because the station network is
gone, the recovery AP (see `docs/NETWORK.md`) brings the appliance back on a
local hotspot at `192.168.66.1/24` after `RECOVERY_AP_TIMEOUT` seconds. Connect
to the `RECOVERY_AP_SSID`, then SSH to the hotspot address.

## 2. SSH recovery

If the host is reachable but the Web UI is not:

```bash
ssh kvm@taishankvm.local
systemctl status one-kvm
journalctl -u one-kvm -n 100 --no-pager
```

## 3. UART console

UART remains the vendor serial console and the last-resort recovery path. Do not
remove the vendor serial console until the appliance is stable and hardening is
explicitly requested.

Use it when:

- Wi-Fi fails to come up and the recovery AP does not start;
- SSH is unreachable and the login account is broken;
- the board fails to boot;
- the USB gadget is stuck.

Connect a 3.3 V USB-UART adapter to the board's debug UART (TX/RX/GND, crossed),
then `picocom -b 1500000 /dev/ttyUSB0` (baud as documented by the vendor) and
log in over the serial console.

## 4. ADB debug mode (opt-in only)

ADB is disabled by default. It is mutually exclusive with One-KVM's USB Device
Controller ownership, so enabling it requires stopping One-KVM and releasing the
gadget.

Enable:

```bash
sudo /usr/local/sbin/adb-debug-enable.sh
```

Disable and hand the UDC back to One-KVM:

```bash
sudo /usr/local/sbin/adb-debug-disable.sh
```

Sequence enforced by the helper scripts:

1. stop `one-kvm.service`;
2. unbind and clean the current ConfigFS gadget;
3. unmask and start ADB;
4. on disable, reverse the order and re-mask ADB.

Both scripts take `/run/one-kvm-adb.lock` so they can never run concurrently.
`ENABLE_ADB_DEBUG=1` (in `config/build.env` or `/etc/default/one-kvm-adb`) is
required to enable the mode.

Never run ADB and One-KVM as concurrent owners of the same UDC.

## 5. MaskRom recovery

Use MaskRom only when the board does not boot at all. On the TaishanPi, enter
MaskRom mode per the vendor documentation (hold the MaskRom/recovery button
while powering/pressing reset), then connect USB to the host and confirm the
Rockchip USB device appears:

```bash
lsusb | grep -i rockchip
```

The loader/upgrade tool (for example `rkdeveloptool` or Rockchip
`upgrade_tool`) can then reflash the loader and images. Confirm exact tool
flags against your installed tool version before use. See `docs/FLASHING.md`.

## 6. Identifying the fault class

`scripts/verify/target-smoke.sh` (run on the target with `sudo`) categorizes
failures as kernel/UDC, ADB/gadget ownership, video capture, Wi-Fi, or One-KVM
service. Use it before attempting recovery so you fix the right layer.
