# Build

This document is the exact, reproducible workflow from an empty repository plus
a downloaded vendor SDK to final artifacts in `dist/`. It follows the Make
targets defined in the top-level `Makefile` and the contract in `AGENTS.md`.

The vendor SDK is not present in this repository yet (State A). Everything that
can be prepared without it is in place. SDK-dependent steps activate once the
SDK is placed. Where a detail depends on the real SDK, this document says so
and describes the detection mechanism instead of hard-coding a guess.

---

## 1. Host prerequisites

The build host needs:

| Requirement | Notes |
|---|---|
| Linux host | x86_64 recommended |
| Docker or Podman | Docker commands are the documented default |
| Git | For the repository and vendor repo tooling |
| Make | Drives the pipeline |
| Disk space | The SDK and build output are large; plan for tens of GB |
| Network | To pull the builder base image and packages |

The builder container is a disposable Ubuntu 22.04 sandbox. It may need
`--privileged` for vendor rootfs, chroot, binfmt, and mount workflows. The
repository is bind-mounted into the sandbox. The multi-gigabyte SDK is never
copied into the image.

Validate the host first:

```bash
make doctor
```

`make doctor` checks Docker, Git, SDK presence, and configuration. It is safe
to re-run.

---

## 2. Build the builder and enter it

```bash
make builder     # build taishanpi-kvm-builder:22.04
make shell       # optional interactive privileged shell
```

`make builder` runs `scripts/host/build-builder.sh`. `make shell` runs
`scripts/host/enter-builder.sh` and drops you into the sandbox with the repo at
`/work`.

To run a single command inside the sandbox without an interactive shell:

```bash
scripts/host/enter-builder.sh -- scripts/kernel/build.sh
```

The Makefile uses this same wrapper for every in-builder target, so you rarely
need to call it directly.

Builder design notes:

- Default `python` resolves to Python 3 (`python-is-python3`).
- Python 2.7 is installed only for legacy vendor scripts and must be invoked
  explicitly as `python2.7`.
- A non-root `builder` user has passwordless sudo for vendor scripts that need
  both user and root steps.
- `ENABLE_CCACHE=1` at image build time adds ccache. Correctness never depends
  on it.

---

## 3. Place the SDK (State A to B)

Download the multi-part SDK and place the extracted folder here:

```text
sdk/vendor/tspi_1m_linux_kernel6.1_sdk_20260807/
```

The folder should contain the vendor `extract_sdk.sh` and the SDK tarballs.
Packaging details vary by release. The scripts detect what is present; they do
not assume a fixed internal layout.

Directory names can be overridden in `config/versions.env` via
`SDK_VENDOR_DIRNAME` and `SDK_WORK_DIRNAME` if the vendor uses different names.

The SDK intake and work trees are gitignored. Do not commit them.

---

## 4. SDK lifecycle states

The project supports five states, detected by `scripts/lib/sdk.sh` and reported
by `make sdk-check`.

| State | Meaning | Next action |
|---|---|---|
| A | SDK absent | Place the SDK under `sdk/vendor/` |
| B | Downloaded multi-part folder present | `make sdk-extract` |
| C | Extracted tree with `.repo/`, worktree not synced | `make sdk-sync` |
| D | Fully synced worktree (kernel tree present) | `make baseline` |
| E | Baseline build artifacts exist | Proceed to patch and build |

Detection probes for well-known markers and reports what it actually finds. It
does not hard-code the 20260807 internal layout beyond those markers.

### State A: SDK absent

The repository is fully scaffolded. `make all` stops with guidance:

```text
SDK absent, run: make sdk-extract && make sdk-sync after placing it.
```

### State B: downloaded multi-part folder present

The vendor extractor is available. Run the idempotent extraction:

```bash
make sdk-check
make sdk-extract
```

### State C: extracted tree, worktree not synced

The tree has `.repo/` but the worktree is incomplete. Use the vendor repo
tooling with local objects:

```bash
make sdk-sync
```

The sync is local-first. Do not substitute a network-heavy repo sync if the SDK
is packaged for local sync.

### State D: fully synced worktree

The kernel tree and device configuration are present. Run SDK introspection
before patching. Findings are persisted to `docs/STATUS.md` and/or a generated
`build/sdk-inspection.txt`.

### State E: baseline build artifacts exist

The unmodified vendor build has produced artifacts. You can now apply our
patches with confidence that the toolchain is healthy.

---

## 5. Inspect the SDK

```bash
make sdk-check
```

`make sdk-check` runs `scripts/sdk/inspect.sh`. It detects the state and
inspects the vendor tree. The inspection identifies, as the SDK allows:

- the board lunch/config target;
- the selected kernel tree;
- the selected board DTS/DTSI;
- the Debian/rootfs build entrypoint;
- the image packaging entrypoint;
- the boot partition and image layout.

These are DETECTED values, not fixed facts. Record them in `docs/STATUS.md`.

---

## 6. Baseline build first

```bash
make baseline
```

`make baseline` runs `scripts/sdk/baseline-build.sh` and performs the smallest
practical unmodified vendor build. Logs are captured under `build/logs/`.

Why baseline first: it separates "the vendor SDK is broken" from "our patches
are broken". If the baseline fails, the problem is in the host dependencies,
the SDK extraction or sync, or the vendor source. Fix that before touching the
kernel. Do not hide errors with `|| true`.

If the baseline fails, identify the layer:

- host dependency problem: fix the builder image or host;
- SDK extraction or sync problem: re-run `make sdk-extract` or `make sdk-sync`;
- vendor source problem: record it precisely as an external blocker;
- repository problem: fix it directly.

---

## 7. Patch and build the kernel

```bash
make kernel-detect     # find the active board DTS and DWC3 node
make patch             # apply the DWC3 peripheral-mode patch (idempotent)
make kernel-configure  # apply the required kernel config fragment
make kernel            # configure + build + verify effective .config and DTB
```

`make kernel` depends on `patch` and `kernel-configure`, then runs
`scripts/kernel/build.sh` and `scripts/kernel/verify.sh`.

What the patch does: it forces the TaishanPi Type-C DWC3 controller to
`dr_mode = "peripheral"`. It patches only the selected TaishanPi board path,
never every Rockchip board. The patch is stored under `patches/kernel/` and is
applied idempotently (`git apply --check` first, skip if already applied).

What the config does: it enables the USB gadget, ConfigFS, and UVC/V4L2
capabilities listed in `config/kernel-required.config`. Built-in (`=y`) is
preferred for appliance-critical gadget pieces.

Verification is against the **effective generated `.config`**, not a defconfig
fragment. `scripts/kernel/verify.sh` checks every required symbol and reports
deviations. Where practical, the built DTB is decompiled to confirm the
effective DWC3 mode.

If a required symbol is renamed or unavailable in the 20260807 kernel,
investigate the vendor Kconfig and document the equivalent. Do not force a
nonexistent symbol.

Re-check at any time:

```bash
make kernel-verify
```

---

## 8. Build the rootfs

```bash
make rootfs
make rootfs-verify
```

`make rootfs` runs `scripts/rootfs/build.sh`. It starts from the SDK-supported
Debian/rootfs path, then customizes:

1. Build the vendor-supported Debian rootfs.
2. Inspect its package set and board-specific additions.
3. Keep the firmware, modules, udev, and systemd pieces required by AP6212
   Wi-Fi, DWC3, UVC, storage/eMMC, and board initialization.
4. Apply `config/packages-target.txt`.
5. Remove only clearly unnecessary general-purpose packages.
6. Apply `rootfs-overlay/`.
7. Install and pin the One-KVM ARM64 package.
8. Enable NetworkManager.
9. Enable SSH.
10. Disable or mask the vendor ADB gadget startup.
11. Load `libcomposite` as required.
12. Configure hostname and mDNS.
13. Configure log rotation and journald limits for eMMC.
14. Verify no target Docker or container runtime is installed.
15. Produce a package manifest.

Do not aggressively purge vendor packages until their purpose is understood.

### SSH and account policy

Defaults, configurable in `config/build.env`:

```text
hostname: taishankvm
user: kvm
root SSH login: disabled
SSH service: enabled
public-key auth: enabled
password auth: development-only/configurable
```

A production build should fail or loudly warn if neither an SSH public key nor
an explicitly approved password-auth development mode is configured.

### Wi-Fi preset from gitignored config

Station Wi-Fi credentials come from `config/local.env`, which is gitignored.
Copy the template and fill it in:

```bash
cp config/local.env.example config/local.env
# edit config/local.env: WIFI_SSID, WIFI_PSK, WIFI_COUNTRY, SSH key, recovery AP
```

The build injects these values at build time. The PSK is never written to logs
or tracked files. `scripts/lib/common.sh` provides `sanitize_stream` to mask
secret-looking `KEY=VALUE` pairs in captured output.

Never commit `config/local.env`. Never print a PSK.

### One-KVM

One-KVM is pinned in `config/versions.env` (`ONE_KVM_VERSION`). The install
path prefers the official ARM64 `.deb`, staged under the gitignored
`downloads/` directory, and uses the package's own systemd unit with only
minimal drop-ins. There is no Docker on the target.

---

## 9. Package images and write the manifest

```bash
make image
make image-manifest
```

`make image` runs `scripts/image/build.sh` and uses the actual vendor SDK
packaging flow. `make image-manifest` runs `scripts/image/manifest.sh` and
writes:

```text
dist/MANIFEST.txt
dist/SHA256SUMS
```

Artifacts collected under `dist/` may include, depending on the real vendor
layout:

```text
boot.img
rootfs.img
uboot.img
MiniLoaderAll.bin
parameter.txt
update.img
*.dtb
```

Do not assume every item exists. Inspect the SDK and collect what it actually
produces.

`dist/MANIFEST.txt` records:

- build timestamp;
- SDK name and date;
- SDK/repo manifest revision when available;
- kernel version and commit;
- effective board config;
- One-KVM version;
- target package manifest hash;
- hashes of final artifacts.

`dist/SHA256SUMS` holds the checksums. Both files are gitignored by default;
keep small manifests in Git only where useful.

---

## 10. Validate

```bash
make verify
```

`make verify` runs `scripts/verify/static.sh` and checks the host/static gates:

- builder image builds;
- shell script syntax passes;
- required project files exist;
- no secrets are tracked;
- SDK inspection succeeds;
- kernel effective config contains the required symbols;
- patched DTS/DTB resolves to peripheral mode;
- target rootfs contains SSH and NetworkManager;
- SSH is enabled;
- One-KVM is installed and enabled;
- vendor ADB gadget service is disabled or masked;
- target rootfs has no Docker or containerd unless explicitly requested;
- final artifact hashes exist.

A build is not done merely because compilation exits 0. See
[`VALIDATION.md`](VALIDATION.md) for the full matrix, including the on-device
smoke test.

For the on-device test:

```bash
make target-smoke
```

This prints instructions. Copy `scripts/verify/target-smoke.sh` to the booted
TaishanPi and run it there. It makes no destructive changes.

---

## 11. Full pipeline

```bash
make all
```

`make all` runs `doctor`, `builder`, and `sdk-check`. If the SDK is absent
(State A), it stops with guidance. Otherwise it runs:

```text
baseline -> patch -> kernel -> rootfs -> image -> verify
```

Every target is safe to re-run where practical.

---

## 12. Troubleshooting

The items in this section are marked **verify against the real SDK**. They are
known friction points from vendor Kernel 6.1 SDK workflows, but the 20260807
SDK may differ. Confirm against the actual tree before relying on them.

### Python 2.7 must be invoked explicitly

The builder sets default `python` to Python 3. Some legacy vendor scripts still
call `python` expecting Python 2. If a vendor script fails with a Python 3
syntax or import error, do not change the global `python` symlink. Invoke the
script with `python2.7` explicitly, or patch the vendor script to call
`python2.7`.

Symptom: `SyntaxError` or `ModuleNotFoundError` from a vendor script that looks
old. Fix: run it as `python2.7 script.py`.

### Mirror and package fetch issues

The builder rewrites the Ubuntu archive to a mirror
(`UBUNTU_MIRROR` in `config/versions.env`). If `apt-get update` or package
fetches fail, the mirror may be unreachable from your network. Change
`UBUNTU_MIRROR` to a reachable mirror and rebuild the builder image.

Vendor rootfs builds may fetch Debian packages from their own configured
mirrors. If those fail, check the vendor rootfs configuration and the network
path, not our scripts.

### mksquashfs extern gotcha

Some vendor rootfs flows use `mksquashfs` with an external compressor or
`-comp` option that depends on a tool present on the host. If the rootfs build
fails at the squashfs step with a missing compressor or an "extern" error,
check whether the vendor flow expects a specific `mksquashfs` build or an
external binary. Confirm the exact requirement against the real SDK before
changing anything.

### SDK state looks wrong

If `make sdk-check` reports an unexpected state, inspect the markers it prints:
work tree path, `.repo/` presence, `device/rockchip` presence, kernel tree
presence, and `output/` presence. The detection is marker-based. If the vendor
uses different directory names, override `SDK_VENDOR_DIRNAME` or
`SDK_WORK_DIRNAME` in `config/versions.env`.

### Baseline fails

Do not apply patches on top of a broken baseline. Fix the baseline first. The
logs under `build/logs/` show which layer failed. See section 6.

---

## 13. Flashing is manual

The build tooling does not flash hardware. It does not write raw block devices,
repartition the host, or invoke destructive Rockchip flashing commands. The
final flashing step is manual and explicit.

`make image` and `make image-manifest` produce artifacts and checksums. They
stop there. See [`FLASHING.md`](FLASHING.md) for the manual procedure, and
[`RECOVERY.md`](RECOVERY.md) for UART, ADB debug, and MaskRom recovery.

---

## 14. Related documents

- [`ARCHITECTURE.md`](ARCHITECTURE.md) for boundaries and the pipeline map.
- [`HARDWARE.md`](HARDWARE.md) for wiring and USB roles.
- [`VALIDATION.md`](VALIDATION.md) for the full test matrix.
- [`FLASHING.md`](FLASHING.md) for the manual flashing procedure.
- [`STATUS.md`](STATUS.md) for current implementation status.
