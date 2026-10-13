# TaishanPi RK3566 One-KVM Appliance

Reproducible build of an IP-KVM appliance for the **LCKFB TaishanPi / 泰山派
RK3566** (1M class) board, based on the vendor Linux 6.1 SDK
`tspi_1m_linux_kernel6.1_sdk_20260807`.

The target is a **KVM appliance**, not a general-purpose server:

- Rockchip/LCKFB vendor U-Boot + vendor Linux 6.1 board support.
- Minimal Debian ARM64 userspace from the vendor-supported rootfs path.
- **One-KVM Rust** installed natively — no Docker/containerd on the target.
- Type-C DWC3 forced to **USB peripheral** mode for HID + virtual media.
- Type-A as USB **host** for a generic UVC HDMI capture card.
- AP6212 onboard Wi-Fi as the primary network, with an optional recovery AP.
- OpenSSH enabled at boot, independent of ADB.
- UART documented as the emergency console.
- Vendor ADB USB gadget disabled by default.

`AGENTS.md` is the authoritative project contract. `OMP_PROJECT_PROMPT.md`
describes the intended implementation workflow. This README is the quick
happy path.

## Status

The vendor SDK is **not present yet** (State A). All repository scaffolding,
scripts, builder, configuration, and documentation are in place; SDK-dependent
steps activate automatically once the SDK is placed. See
[`docs/STATUS.md`](docs/STATUS.md).

## Quick start

```bash
# 1) Validate the host and inspect config
make doctor

# 2) Build the Ubuntu 22.04 build sandbox (Docker/Podman on the dev host only)
make builder
make shell                 # optional interactive shell inside the builder

# 3) Place the SDK (see sdk/README.md), then:
make sdk-check             # detect state (A..E) + inspect vendor tree
make sdk-extract           # idempotent extraction
make sdk-sync              # idempotent local .repo sync

# 4) Build the appliance
make baseline              # smallest unmodified vendor build (proves toolchain)
make patch                 # DWC3 -> peripheral mode (idempotent)
make kernel                # configure + build + verify effective .config/DTB
make rootfs                # minimal Debian + SSH + NetworkManager + One-KVM
make image                 # package vendor images
make image-manifest        # dist/MANIFEST.txt + dist/SHA256SUMS

# 5) Validate (non-destructive)
make verify
```

`make all` runs the safe pipeline and stops with guidance if the SDK is absent.

## Configuration

| File | Committed? | Purpose |
|------|-----------|---------|
| `config/versions.env` | yes | Pinned SDK / One-KVM / builder versions |
| `config/build.env.example` | yes | Non-secret build options template |
| `config/build.env` | **no** (gitignored) | Your local non-secret overrides |
| `config/local.env.example` | yes | Secrets template (empty) |
| `config/local.env` | **no** (gitignored) | Real Wi-Fi / SSH / recovery secrets |
| `config/packages-target.txt` | yes | Explicit target package baseline |
| `config/kernel-required.config` | yes | Required effective kernel symbols |

**Never commit `config/local.env`.** Station Wi-Fi credentials are injected at
build time from `config/local.env`; the password is never written to logs or
tracked files. The preset station SSID is `DIY-K3`; see
[`docs/NETWORK.md`](docs/NETWORK.md).

## Repository layout

```text
builder/          Ubuntu 22.04 build sandbox (Dockerfile, entrypoint)
config/           Versions, build options, secrets templates, manifests
patches/kernel/   Reproducible kernel/device-tree patches
rootfs-overlay/   Files merged into the target rootfs
scripts/          host | sdk | kernel | rootfs | image | verify | lib
sdk/vendor/       Downloaded SDK intake (gitignored)
sdk/work/         Extracted/synced SDK tree (gitignored)
docs/             Architecture, hardware, build, network, recovery, ...
dist/             Final flashing artifacts (gitignored)
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — build/target boundaries and topology
- [`docs/BUILD.md`](docs/BUILD.md) — full reproducible build workflow
- [`docs/HARDWARE.md`](docs/HARDWARE.md) — Y-cable, VBUS safety, USB roles, UVC
- [`docs/NETWORK.md`](docs/NETWORK.md) — station Wi-Fi, recovery AP, mDNS, SSH
- [`docs/RECOVERY.md`](docs/RECOVERY.md) — UART, ADB debug, MaskRom, network recovery
- [`docs/FLASHING.md`](docs/FLASHING.md) — manual flashing procedure
- [`docs/VALIDATION.md`](docs/VALIDATION.md) — static and on-device tests
- [`docs/STATUS.md`](docs/STATUS.md) — current implementation status

## Safety

- No hardware flashing and no raw block-device writes are performed by the
  tooling — the final flashing step is manual and explicit.
- Vendor ADB never contends with One-KVM for the USB Device Controller.
- The builder container is a disposable sandbox and may require `--privileged`.
