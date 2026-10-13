# Validation

Validation has three layers: host/static gates, the on-device smoke test, and
the functional acceptance checklist.

## Host / static gates

Run on the development host:

```bash
make verify
```

`scripts/verify/static.sh` checks:

- every required project file exists;
- `bash -n` passes on all scripts;
- shellcheck is clean (if installed);
- every script referenced by the `Makefile` exists;
- `config/local.env` and `config/build.env` are not tracked by git;
- no tracked file contains the literal Wi-Fi or recovery PSK.

Use `make verify`'s `--quick` variant for a fast pass that skips shellcheck and
the secrets scan.

Additional host gates are run by the build targets themselves:

- `make kernel` ends with `scripts/kernel/verify.sh`, which checks every symbol
  in `config/kernel-required.config` against the **effective** `.config` and
  confirms the built DTB sets `&usbdrd_dwc3` to `dr_mode = "peripheral"`.
- `make rootfs-verify` checks the unpacked rootfs for SSH, NetworkManager, the
  Wi-Fi profile, native One-KVM, masked ADB, `libcomposite`, and the absence of
  Docker/containerd/snapd/cloud-init.

## On-device smoke test

Copy `scripts/verify/target-smoke.sh` to the booted board and run:

```bash
sudo bash target-smoke.sh
```

It performs read-only checks and prints a categorized verdict distinguishing:

- **kernel / UDC failure**: no UDC in `/sys/class/udc`, configfs not mounted;
- **ADB / gadget ownership conflict**: a legacy `g_*` module or active `adbd`;
- **video capture failure**: no UVC device or no `/dev/video*`;
- **Wi-Fi failure**: `wlan0` missing or NetworkManager inactive;
- **One-KVM service failure**: unit not enabled/active.

## Functional acceptance checklist

Testable criteria from AGENTS.md section 18.3. Map each to the command that
proves it.

| # | Criterion | Proof |
|---|-----------|-------|
| 1 | Cold-boots without keyboard/display | power-cycle, observe Wi-Fi association |
| 2 | Joins station Wi-Fi or enters recovery AP | `nmcli device status` |
| 3 | SSH reachable | `ssh kvm@taishankvm.local` |
| 4 | `wlan0` stable | `ip -brief addr show wlan0` |
| 5 | UDC appears | `ls /sys/class/udc` |
| 6 | UVC capture card streams | `v4l2-ctl --list-devices`, `v4l2-ctl -d /dev/video0 --list-formats-ext` |
| 7 | One-KVM Web UI reachable | browse `http://<host>:8080` |
| 8 | Managed PC sees keyboard/mouse gadget | `lsusb` on the managed PC |
| 9 | Keyboard works in BIOS/UEFI | interact at POST |
| 10 | Relative/absolute mouse works | move pointer in the Web UI |
| 11 | Virtual media attach/detach | mount then eject an ISO in the Web UI |
| 12 | Reboot returns to healthy state | `reboot`, repeat checks 2-5 |
| 13 | ADB not occupying the UDC | `systemctl is-active adbd` returns inactive |

### Expected operating point

Video capture targets MJPEG at 1920x1080, 30 FPS. 1080p60 is not a V1
requirement.

## Interpreting failures

- Kernel/UDC and video failures point at the kernel `.config`/DTB; re-run
  `make kernel-verify`.
- Gadget-ownership conflicts point at vendor ADB init; re-check the masking in
  `scripts/rootfs/customize.sh`.
- Wi-Fi failures point at the profile generated from `config/local.env`; verify
  the SSID and that the keyfile mode is `0600`.
- One-KVM service failures: `systemctl status one-kvm` and
  `journalctl -u one-kvm -n 100`.
