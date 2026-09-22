# OMP project bootstrap / implementation prompt

Work in the current repository and complete the TaishanPi RK3566 One-KVM appliance project described by `AGENTS.md`.

`AGENTS.md` is the authoritative project contract. Read it completely before making changes. Then inspect the current directory and continue from the repository's real state rather than assuming it is empty.

## Main objective

Build a reproducible project that can take the LCKFB SDK:

`tspi_1m_linux_kernel6.1_sdk_20260807`

and produce a TaishanPi RK3566 IP-KVM system with:

- Rockchip/LCKFB vendor Linux 6.1 + vendor U-Boot.
- Minimal Debian ARM64 userspace based on the vendor-supported Debian/rootfs path.
- Native One-KVM Rust installation on the TaishanPi.
- No Docker/containerd on the target system.
- Type-C DWC3 in USB peripheral mode for One-KVM HID + virtual media.
- Type-A as USB Host for a generic UVC HDMI capture card.
- AP6212 onboard Wi-Fi as the primary network.
- OpenSSH installed, enabled, and available after boot independently of ADB.
- UART documented as the emergency console.
- Vendor ADB USB Gadget disabled by default; if ADB debug support is retained, make it explicitly opt-in and mutually exclusive with One-KVM's UDC ownership.
- Optional Wi-Fi recovery AP as described in `AGENTS.md`.
- A reproducible Ubuntu 22.04 Docker build environment on the development host only.

## How to work

Do not only write a plan. Implement the project.

Start by:

1. Read `AGENTS.md`.
2. Run `pwd`, inspect the directory tree, and run `git status --short`.
3. Read all existing relevant Dockerfiles, scripts, Makefiles, docs, and configuration files before replacing or restructuring them.
4. Create/update `docs/STATUS.md` with:
   - DONE
   - IN PROGRESS
   - BLOCKED
   - NEXT
5. Determine whether `tspi_1m_linux_kernel6.1_sdk_20260807` is already present anywhere under the project's intended `sdk/` intake paths.
6. Preserve all existing user work. Do not use destructive Git cleanup/reset/stash commands.

## If the SDK is not present yet

Do not stop at "SDK missing".

Complete everything that can safely be prepared without it:

- repository layout;
- `.gitignore` and `.dockerignore`;
- Ubuntu 22.04 builder Dockerfile;
- builder entrypoint;
- host doctor/build/enter scripts;
- SDK detection/extraction/sync scripts;
- Makefile orchestration;
- configuration templates;
- target package manifest;
- kernel required-config manifest;
- rootfs overlay skeleton;
- SSH policy/config templates;
- NetworkManager/Wi-Fi templates;
- recovery AP service/script skeleton where practical;
- ADB-disable/recovery script skeletons where practical;
- One-KVM native-install script structure;
- image collection/manifest scripts;
- static verification scripts;
- target smoke-test script;
- all project documentation required by `AGENTS.md`.

Then make the SDK intake path unambiguous. Prefer:

`sdk/vendor/tspi_1m_linux_kernel6.1_sdk_20260807/`

for the downloaded multi-part folder and:

`sdk/work/tspi-linux-sdk/`

for the extracted/synced working tree, unless the existing project already has a compatible convention.

Print the exact next command(s) the user should run after placing the SDK.

Do not invent the internal 20260807 SDK file layout if you cannot inspect it yet. Mark SDK-dependent details as detection logic, not hard-coded assumptions.

## If the SDK is present

Proceed as far as possible automatically through the safe build pipeline.

### Phase 1 — SDK inspection

Detect and document:

- whether this is the downloaded multi-part folder, an extracted `.repo` folder, or a fully synced worktree;
- actual `extract_sdk.sh` behavior;
- actual local repo sync command;
- actual lunch/board config for TaishanPi RK3566 1M V10;
- actual `kernel-6.1` tree;
- actual board DTS/DTSI selected by this board;
- actual Debian/rootfs build path;
- actual image packaging path;
- actual output artifact names and locations.

Write findings to `docs/STATUS.md` and a generated SDK-inspection report.

Never rely solely on old tutorial filenames when the SDK can tell you the truth.

### Phase 2 — baseline

Perform the smallest practical unmodified vendor build that proves the toolchain and SDK are healthy before applying our One-KVM patches.

Capture logs under `build/logs/`.

If the baseline fails:

- identify whether the problem is host dependency, SDK extraction/sync, vendor source, or our repository;
- fix repository/builder problems directly;
- record genuine external/vendor blockers precisely;
- do not hide errors with `|| true`.

### Phase 3 — kernel/device-tree patching

Identify the active Rockchip DWC3 device-tree node and produce a reproducible, idempotent patch that changes the TaishanPi Type-C controller's effective mode to:

`dr_mode = "peripheral";`

Patch only the selected TaishanPi board path.

Add/verify the effective kernel configuration required by `AGENTS.md`, including USB ConfigFS HID, mass storage, UVC/V4L2, TUN, and relevant optional USB Ethernet functions.

Prefer a config fragment or scripted `scripts/config` workflow compatible with the vendor tree.

After configuration/build, verify the actual generated `.config`.

Where practical, decompile/inspect the generated DTB to confirm the effective DWC3 mode.

### Phase 4 — Debian rootfs

Use the SDK-supported Debian build path as the integration baseline.

Do not jump straight to an independent `debootstrap --variant=minbase` rootfs unless you first prove how to preserve all vendor board integration.

Create a minimal appliance userspace by:

- keeping required AP6212 firmware/modules/board integration;
- using `config/packages-target.txt`;
- installing NetworkManager and Wi-Fi tooling;
- installing/enabling OpenSSH;
- configuring the non-root maintenance account;
- adding mDNS if selected;
- adding useful debugging tools specified by `AGENTS.md`;
- keeping Python 3;
- excluding Docker, containerd, snapd, cloud-init, desktop/GUI stacks, and target build toolchains;
- limiting journald/log growth appropriately for eMMC;
- applying `rootfs-overlay/`.

Never commit real Wi-Fi credentials or private SSH keys.

### Phase 5 — SSH/network provisioning

Implement:

- SSH enabled at boot;
- root SSH login disabled;
- public-key authentication preferred;
- configurable development password mode only when explicitly enabled in local config;
- NetworkManager station-mode config injection from a gitignored `config/local.env`;
- optional recovery AP if station connectivity cannot be established;
- `taishankvm.local` or the documented selected mDNS hostname.

Build scripts must not print Wi-Fi PSKs or private secrets.

### Phase 6 — ADB / UDC ownership

Inspect the vendor rootfs for:

- `adbd`;
- Rockchip USB gadget init scripts;
- services/scripts such as `.usb_config`, `usbdevice`, or equivalents;
- any unit/init hook that binds the UDC.

Normal production boot must leave UDC ownership available to One-KVM.

Disable/mask the vendor ADB gadget startup reproducibly.

If preserving ADB as a development option is feasible, add explicit mutually-exclusive helper scripts/services:

- stop One-KVM;
- unbind/clean its gadget;
- start ADB;
- reverse safely when disabling ADB.

Do not require ADB for normal management.

### Phase 7 — native One-KVM

Inspect the current official One-KVM Rust release/documentation.

Pin an explicit ARM64 version in `config/versions.env`.

Prefer the official ARM64 `.deb` when available.

Implement a reproducible target-rootfs installation path and use the package's own systemd unit when appropriate, adding only minimal drop-ins.

Do not install Docker on the target.

Verify One-KVM is enabled at boot and its logs are available via `journalctl`.

### Phase 8 — image/package generation

Use the actual vendor SDK packaging flow.

Collect all real flashing artifacts into `dist/` and generate:

- `dist/MANIFEST.txt`
- `dist/SHA256SUMS`

Include versions/revisions described by `AGENTS.md`.

Do not automatically flash hardware.

### Phase 9 — validation

Run all non-destructive validation available on the host.

At minimum validate:

- builder image builds;
- shell syntax;
- SDK inspection;
- effective kernel config;
- effective DWC3 peripheral mode;
- rootfs contains/enables SSH;
- NetworkManager is installed/enabled;
- One-KVM is natively installed/enabled;
- ADB gadget is not enabled for normal boot;
- Docker/containerd are absent from target rootfs;
- final artifact manifest/checksums exist.

Create/update `scripts/verify/target-smoke.sh` for the real board.

## Builder requirements

Improve the existing Dockerfile rather than blindly replacing it.

Use Ubuntu 22.04.

Important correction: do not set `/usr/bin/python` to Python 2.7 globally. Default `python` must be Python 3. Retain Python 2.7 only if the real SDK needs it and invoke it explicitly.

Install the dependency set required by the current LCKFB Kernel 6.1 SDK and any additional tools demonstrated by actual SDK scripts/errors.

Do not COPY the multi-gigabyte SDK into the Docker image. Bind-mount the repository.

Document and implement a command equivalent to a privileged builder session when required by rootfs/chroot/binfmt operations.

## Command interface

Converge on a simple top-level command surface, preferably:

```bash
make doctor
make builder
make shell
make sdk-check
make sdk-extract
make sdk-sync
make baseline
make patch
make kernel
make rootfs
make image
make verify
make all
```

If the existing repository already has a better convention, preserve it and provide equivalent discoverable targets.

Each target should be safe to re-run where practical.

## Safety rules

Do not run:

- `git reset --hard`
- `git clean -fd`
- `git checkout .`
- blanket `git restore`
- destructive partitioning
- raw writes to host block devices
- Rockchip flashing commands against hardware

unless the user explicitly asks for the destructive hardware operation.

Do not delete unknown files.

Do not silently overwrite user configuration.

Do not hard-code or commit secrets.

Do not mark the project complete solely because compilation succeeds.

## Completion standard

Continue through all safe phases that the current repository and available SDK allow.

When you finish this session, provide a concise report containing:

1. what you changed;
2. exact files created/modified;
3. exact commands that now work;
4. current build/validation results;
5. any blocker with its concrete error/log path;
6. if the SDK is absent, the exact placement path and next command;
7. if artifacts were built, the exact `dist/` files and checksums;
8. the remaining physical-board validation steps.

Keep `docs/STATUS.md` synchronized with that report.

Do not merely propose the structure—leave the repository in a runnable, reviewable state.
