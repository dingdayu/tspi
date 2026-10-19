# Flashing (manual)

> The build tooling and coding agents never flash hardware. There is no
> automatic flashing target. The steps below are performed by a human,
> explicitly. This protects the board, the host, and any attached storage.

## Pre-flight checklist

1. Verify artifact integrity:
   ```bash
   cd dist
   sha256sum -c SHA256SUMS
   ```
2. Confirm the artifacts match the manifest: `dist/MANIFEST.txt`.
3. Confirm the correct Rockchip device is connected (not a host disk):
   ```bash
   lsusb | grep -i rockchip
   ```
4. Confirm power and USB wiring, including the Y-cable VBUS isolation described
   in `docs/HARDWARE.md`.
5. Back up anything on the board you need. Flashing is destructive to the
   target storage.

## Artifacts

Produced by `make image` and collected into `dist/` (only artifacts that the
vendor SDK actually produces are present; `make image-manifest` records which
were found):

| Artifact | Purpose |
|----------|---------|
| `MiniLoaderAll.bin` | Rockchip loader |
| `uboot.img` | Vendor U-Boot |
| `boot.img` | Kernel + DTB |
| `rootfs.img` | Debian appliance rootfs |
| `parameter.txt` | Partition table |
| `update.img` | Combined image (if produced) |
| `*.dtb` | Device trees (reference) |

## Modes

### Loader mode

With the board bootable but not fully running, put it into Loader mode per the
vendor procedure, then flash the loader and images. Verify the exact subcommands
against your installed tool:

```bash
rkdeveloptool ld                       # list devices (tool-specific)
rkdeveloptool db MiniLoaderAll.bin     # download loader to RAM
rkdeveloptool wl 0x0 MiniLoaderAll.bin
rkdeveloptool wl 0x4000 uboot.img
rkdeveloptool rd                       # reset
```

### MaskRom mode

Use when the board does not boot. Enter MaskRom per the vendor documentation,
confirm `lsusb | grep -i rockchip`, then use the loader/upgrade tool to recover.

### Single update image

If `update.img` was produced, the vendor upgrade tool can flash it in one step.
Confirm the tool version and flags before use.

## After flashing

1. Power-cycle the board.
2. Wait for boot, then find it on the network (station Wi-Fi or recovery AP).
3. `ssh kvm@taishankvm.local`.
4. Run the smoke test:
   ```bash
   sudo bash scripts/verify/target-smoke.sh
   ```
5. Check `docs/VALIDATION.md` for the full acceptance checklist.

## Safety notes

- Never write raw block devices on the host.
- Never invoke Rockchip flashing against a device you have not positively
  identified.
- Tool names and flags (`rkdeveloptool` vs `upgrade_tool`) differ between
  versions; confirm against your installed tool's help output.
- The flashing tools (`RKDevTool`, `DriverAssistant`, `SDDiskTool`) are
   available from the LCKFB TaishanPi
   [download center](https://wiki.lckfb.com/zh-hans/tspi-rk3566/download-center.html)
   (第07章.【立创·泰山派】开发工具).
