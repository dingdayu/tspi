# Implementation Status

Last updated: 2026-10-14. Full pipeline completed inside the builder container:
the vendor **Debian** appliance rootfs was built, customized (kvm account, SSH,
NetworkManager, One-KVM), repacked, and packaged — `dist/update.img` and
`dist/rootfs.img` now carry the customized rootfs. `make verify` → **PASS**.

## DONE

Repository, builder, scripts, overlay, configuration, and documentation are all
in place and pass static validation (`make verify`).

- **Layout** per AGENTS.md section 7: `builder/`, `config/`, `patches/kernel/`,
  `rootfs-overlay/`, `scripts/{lib,host,sdk,kernel,rootfs,image,verify}/`,
  `docs/`, `sdk/{vendor,work}/`, `downloads/`, `build/`, `dist/`.
- **Ignores**: `.gitignore` (secrets, SDK trees, outputs, `.omo/`, `.codegraph/`)
  and `.dockerignore`.
- **Makefile**: `doctor builder shell sdk-check sdk-extract sdk-sync baseline
  kernel-detect patch kernel-configure kernel kernel-verify rootfs rootfs-verify
  image image-manifest verify target-smoke all clean` (verified with `make help`).
- **Builder**: `builder/Dockerfile` (Ubuntu 22.04, default `python` = Python 3),
  `builder/entrypoint.sh`, `builder/README.md`.
- **Config**: `config/versions.env` (One-KVM pinned 0.2.6 / `v260802`),
  `config/build.env.example`, `config/local.env.example`, `config/local.env`
  (gitignored; holds the `DIY-K3` station preset), `config/packages-target.txt`
  (incl. `libudev1`, `libdrm2`, `libasound2`), `config/kernel-required.config`.
- **Script library**: `scripts/lib/common.sh`, `scripts/lib/sdk.sh`
  (SDK state detection A-E).
- **Host scripts**: `doctor.sh` (with `--print-sdk-state`, `--strict`),
  `build-builder.sh`, `enter-builder.sh`.
- **SDK scripts**: `inspect.sh`, `extract.sh`, `sync.sh`, `baseline-build.sh`.
- **Kernel scripts**: `detect-board.sh`, `patch.sh` (idempotent DWC3 -> peripheral),
  `configure.sh`, `build.sh`, `verify.sh` (effective `.config` + DTB check).
- **Rootfs scripts**: `build.sh`, `customize.sh` (packages, overlay, account,
  SSH, Wi-Fi preset, mDNS, recovery AP, ADB masking), `install-one-kvm.sh`,
  `verify.sh`.
- **Image scripts**: `build.sh`, `collect.sh`, `manifest.sh`.
- **Verify scripts**: `static.sh`, `target-smoke.sh`.
- **Overlay**: modules-load, sshd policy, NetworkManager defaults, journald
  limits, recovery-AP service/timer + script, ADB debug enable/disable, udev setup.
- **Docs**: `README.md`, `ARCHITECTURE.md`, `BUILD.md`, `HARDWARE.md`,
  `NETWORK.md`, `RECOVERY.md`, `FLASHING.md`, `VALIDATION.md`, `STATUS.md`.

### Validation results

- `make verify`: **PASS** (all required files present; shell syntax OK; secrets
  not tracked / not leaked; Makefile script references valid).
- `bash -n` across all scripts: clean.
- `bash scripts/host/doctor.sh --print-sdk-state`: prints `A`.
- `make doctor`: OK (2 warnings: no SSH key yet; shellcheck not installed).
- `make sdk-check`: detects State A and prints the placement path.

## IN PROGRESS

None. All SDK-independent work is complete.

## BLOCKED

- Build phases (`baseline`, `patch`, `kernel`, `rootfs`, `image`) require the
  vendor SDK. Currently **State A (SDK absent)**.

## NEXT

1. Install host prerequisites: a running Docker/Podman daemon; optionally
   `shellcheck`.
2. Set `SSH_PUBLIC_KEY_FILE` in `config/local.env` (or accept the password-auth
   fallback). Change `RECOVERY_AP_PSK` from the placeholder.
3. Place the SDK at
   `sdk/vendor/tspi_1m_linux_kernel6.1_sdk_20260807/`.
4. `make builder && make sdk-check && make sdk-extract && make sdk-sync`.
5. `make baseline` (prove the unmodified vendor toolchain).
6. `make patch && make kernel` (DWC3 peripheral; effective `.config`/DTB).
7. `make rootfs && make rootfs-verify`.
8. `make image && make image-manifest`.
9. `make verify`; flash manually per `docs/FLASHING.md`.
10. On the board: `sudo bash scripts/verify/target-smoke.sh`.

## Known follow-ups

- `ONE_KVM_SHA256` is empty; pin it after the first verified `.deb` download
  (`install-one-kvm.sh` logs the computed hash).
- Target rootfs must be **Debian 12+ / Ubuntu 24.04+** because One-KVM 0.2.x
  links `libc >= 2.36`. Confirm the vendor SDK's `RK_DEBIAN_VERSION`.
- Board DTS/DWC3 node identity is detected at build time, not hard-coded.
- `dockerfile` and `Untitled-1.sh` remain at the repository root as preserved
  user notes; they are not used by the pipeline.

---

## SDK download (2026-09-23 → 2026-10-13) — DONE

Reception directory (absolute):
`<project>/sdk/vendor/tspi_1m_linux_kernel6.1_sdk_20260807/`

### DONE

- All **19/19** files present in the reception directory, size-exact;
  total 25,028,964,423 bytes.
- Parts verified from inside the reception directory with the vendor checksum
  lists: `md5sum -c sdk_parts_checksums.md5` and
  `sha256sum -c sdk_parts_checksums.sha256` → **all 12 parts OK for both
  hashes** (exit 0).
- `file_checksums.sha256` and `file_list.txt` present; consumed after extraction
  (not verified in this phase).
- Five parts (`.05 .06 .08 .09 .10`) and the small files were fetched directly;
  the remaining seven (`.00 .01 .02 .03 .04 .07 .11`) had to be fetched manually
  from a different host/IP because the provider routed them to a broken CDN node
  that returned `403 sign error` from this network regardless of signature or
  node. Manual copies were size- and hash-verified here.

### IN PROGRESS

None.

### BLOCKED

None.

### NEXT

1. `make rootfs` — build the Debian rootfs and install One-KVM/overlay. **Requires
   root** (see BLOCKED below).
2. After rootfs customization: `make image` again, then `make verify`.

### Extraction & local sync (2026-10-13) — DONE

- The SDK `.tar.xz` contains only `.repo/` (a repo mirror; 7364 tar entries);
  the worktree is populated afterward by `repo sync -l` (State C → D).
- Extracted streaming: `cat rk3566_linux_sdk_20260806.tar.xz.part.* | tar -xJf -
  -C extracted_sdk`. This avoids the vendor `extract_sdk.sh` intermediate
  `combined.tar` (whose peak usage — parts + 2×uncompressed — could exceed free
  space).
- Extracted contents verified: `sha256sum -c file_checksums.sha256` → **4147/4147
  OK** (exit 0).
- `sdk/work/tspi-linux-sdk` symlinked to the extracted tree; `repo sync -l -j16`
  populated the worktree from local objects (no network); post-sync **State D**
  (`device/rockchip`, `build.sh`, `kernel-6.1`, `.repo` all present).

#### Vendor baseline build (2026-10-13) — DONE (host-side, no Docker)

- Board config: `rockchip_rk3566_taishanpi_1m_v10_defconfig` (auto-detected).
- The documented builder container could not be used: Docker daemon is down,
  there is no systemd, no passwordless `sudo`, `/var/run` is not writable, no
  `podman`; rootless Docker is impossible (seccomp blocks user namespaces:
  `unshare -Ur`/`CLONE_NEWUSER` → `EPERM`; `rootlesskit`/`slirp4netns` absent).
- Instead the vendor build was run **directly in this container** with a minimal,
  no-root userspace overlay:
  - `~/.local/sdk-tools` — symlinks for tools the container lacks, from a
    conda-forge env (`~/.local/sdkbuild`): `flex bc dtc cpio gawk gperf msgmerge
    makeinfo lz4 zstd fdtget fdtput fdtdump fdtoverlay`, plus a patched
    `fakeroot` served from a dedicated prefix `~/.local/sdk-fakeroot` (Buildroot's
    own `fakeroot` hard-codes its host path and shadows the system `libext2fs`).
  - `~/.local/sdk-hdrs` (only `gmp.h`, `mpfr.h`, `mpc.h`) exposed via `CPATH` for
    the vendor `check-kernel.sh`. conda lib/include dirs are deliberately **not**
    exposed, otherwise `check-buildroot.sh` aborts on `libiconv`.
  - Env: `PATH=~/.local/sdk-tools:$PATH CPATH=~/.local/sdk-hdrs`, with
    `LIBRARY_PATH`/`LD_LIBRARY_PATH` unset.
- Result: `./build.sh` completed **all** stages, exit 0 —
  `misc → uboot → kernel → rootfs(buildroot) → recovery-kernel → recovery →
  extra-parts → updateimg → firmware`. Post-build **State E**.
- Artifacts (under `sdk/work/tspi-linux-sdk/`):
  - `output/update/Image/update.img` (~1.0 GiB)
  - `output/firmware/`: `boot.img`(40M), `rootfs.img`(902M), `uboot.img`(4M),
    `MiniLoaderAll.bin`(539K), `recovery.img`(46M), `misc.img`, `oem.img`,
    `userdata.img`, `parameter.txt`, `update.img`
  - `kernel-6.1/arch/arm64/boot/Image.lz4`(17M) and
    `dts/rockchip/tspi-rk3566-user-v10-linux.dtb`
- NOTE: because the builder container is unavailable, `make baseline` (which runs
  through `scripts/host/enter-builder.sh`) was not used; the equivalent vendor
  `./build.sh` was run directly. With a working Docker daemon, `make baseline`
  reproduces the documented container path.

#### Kernel patch + config + verify (2026-10-13) — DONE (host-side)

- Board DTS auto-detected as `tspi-rk3566-user-v10-linux.dts`; its DWC3 node was
  `dr_mode = "otg"`. `scripts/kernel/patch.sh` appended the peripheral override and
  recorded `patches/kernel/0001-tspi-dwc3-peripheral.patch`.
- Config application: the vendor kernel build regenerates `.config` from the
  board defconfig plus the merged fragment `arch/arm64/configs/rk3566.config`, so
  `scripts/kernel/configure.sh` (which edits `.config`) is overwritten by the later
  vendor step. The required symbols were therefore appended to that merged
  fragment (idempotent, marked block) and recorded as
  `patches/kernel/0002-tspi-required-kernel-config.patch`.
- `config/kernel-required.config`: the DWC3 mode is a Kconfig **choice**
  (`HOST` / `GADGET` / `DUAL_ROLE`); the file previously required both
  `USB_DWC3_DUAL_ROLE` and `USB_DWC3_GADGET`, which is impossible. Kept
  `CONFIG_USB_DWC3_DUAL_ROLE=y` (vendor default; builds gadget support) and the
  DTS forces the device role at runtime.
- `scripts/kernel/verify.sh` fixes:
  1. `grep | head` under `set -o pipefail` aborted the whole check on the first
     missing symbol; now it reports every symbol/mismatch.
  2. the DTB check assumed labels are inlined by `dtc -I dtb -O dts`; it now
     resolves the label via `__symbols__` and reads `dr_mode` with `fdtget`.
- Result: `scripts/kernel/verify.sh` → **PASS** — all 15 required symbols present in
  the effective `.config`, and the built DTB has `&usbdrd_dwc3`
  (`/usbdrd/usb@fcc00000`) with `dr_mode = "peripheral"`.
- FOLLOW-UP: `scripts/kernel/configure.sh` is effectively a no-op for this vendor
  flow (its `.config` edits are regenerated). It should be refactored to write the
  merged fragment (as done here) instead of editing `.config`.

#### Image packaging (2026-10-13) — DONE (host-side)

- `scripts/image/build.sh` → vendor `build.sh firmware` + `updateimg` (cached) →
  `scripts/image/collect.sh`; `scripts/image/manifest.sh` → `dist/MANIFEST.txt` +
  `dist/SHA256SUMS`.
- `dist/`: `boot.img`(40M), `rootfs.img`(902M), `uboot.img`(4M),
  `MiniLoaderAll.bin`(539K), `parameter.txt`, `update.img`(~1.0G),
  `tspi-rk3566-user-v10-linux.dtb`; `boot.img`/DTB carry the peripheral-mode change.
- NOTE: the packaged `rootfs.img` is the **buildroot** rootfs from the baseline
  (`RK_ROOTFS_SYSTEM=buildroot`), not the project's customized Debian appliance
  rootfs — see BLOCKED.

### BLOCKED (root required) — Debian rootfs + One-KVM customization

- `scripts/rootfs/build.sh` (default `ROOTFS_SYSTEM=debian`) drives the vendor
  Debian build (`debian/mk-rootfs-bookworm.sh`, `check-debian.sh`, `post-debian.sh`,
  `debian/mk-image.sh`), which use `sudo`/`debootstrap`/`chroot`/`mkfs.ext4`; then
  the project's `unpack_image()` uses `mount -o loop`.
- `scripts/rootfs/customize.sh` + `install-one-kvm.sh` then `chroot` into the
  unpacked tree (with `qemu-aarch64-static`) to install packages, create the
  maintenance account, enable SSH/NetworkManager/mDNS, mask vendor ADB, and extract
  the pinned One-KVM `.deb`.
- This environment has no root, no passwordless `sudo`, user namespaces are blocked
  by seccomp, and no usable Docker daemon — so these steps cannot run here.
- Resolution: run `make rootfs && make image` inside the builder container (needs a
  working Docker daemon) or on a host with root plus `debootstrap`/`live-build`.

### Host / container build fixes (2026-10-13)

Fixes discovered while running the documented pipeline inside the builder
container (each committed separately):

- `scripts/host/enter-builder.sh`
  - do **not** bind-mount `/proc/sys/fs/binfmt_misc` (newer runc rejects it:
    "cannot be mounted because it is inside /proc"); register arm64 on the host
    instead (`docker run --privileged --rm tonistiigi/binfmt --install arm64`).
    Opt back in with `BUILDER_MOUNT_BINFMT=1`.
  - rewrite host `/…` paths under the project root to `/work/…` for the container.
  - do **not** inject `RK_SDK_DIR` (the vendor `build.sh` treats external `RK_*`
    vars as "custom environments" and blocks on `read -t 10`).
- `builder/Dockerfile` — add packages the vendor checks need:
  `debootstrap`, `libgmp-dev libmpfr-dev libmpc-dev`, `gettext` (msgmerge),
  `patch`, `gperf`.
- `scripts/lib/common.sh` — stop exporting our project variables into the vendor
  build. Exported generic names collided with vendor internals:
  `TARGET_ARCH` broke glibc (`LINK.o = $(CC) $(LDFLAGS) $(TARGET_ARCH)` →
  `ld: cannot find arm64`), and `CONFIG_DIR`/`BUILD_DIR` leaked into Buildroot
  (`CONFIG_DIR := $(O)`), breaking libvpx RTCD (`--config=$(CONFIG_DIR)…` →
  malformed path → empty `*_rtcd.h`). They remain available in-shell.
- If a stale Buildroot cache was produced by an earlier host-side run, delete
  `buildroot/output/<config>` (or the affected package build dirs) so it rebuilds
  cleanly in the container.

### Notes on removed tooling

All ad-hoc download tooling created during this phase was removed at the user's
request after the SDK was received and verified: the reusable
`scripts/sdk/download.sh` + `scripts/sdk/download_manifest.py`, the `curl`
resolve-retry loop, the generated wget script, and all manifests/logs/partial
shards. No signed URLs remain anywhere in the repository. `build/` now contains
only `build-builder.log` and `sdk-inspection.txt`.

---

## Docker container build completion (2026-10-14) — DONE

The pipeline was run end-to-end by the user inside the `taishanpi-kvm-builder`
container, with the assistant fixing each blocker as it surfaced.

### DONE

- **Kernel**: DWC3 forced to `dr_mode = "peripheral"`; effective `.config` +
  built DTB verified (`make kernel`).
- **Debian rootfs** (`make rootfs`, vendor `build.sh rootfs`): the vendor
  `check-debian.sh` gate was satisfied, and the SDK's prebuilt
  `debian/linaro-bookworm-*.tar.gz` was extracted + chrooted.
- **Customization** (`scripts/rootfs/customize.sh`): `openssh-server`,
  `network-manager` etc. installed; `kvm` account created (uid 1001, primary
  group the vendor's existing `kvm` group, gid 103) and added to
  `sudo,video,input,plugdev,audio`; Wi-Fi station profile (0600); mDNS/hostname
  `taishankvm`; ADB gadget masked; `libcomposite` in `modules-load.d`; pinned
  One-KVM `.deb` extracted + service enabled.
- **Repack**: the customized tree is repacked with `mkfs.ext4 -d` back into
  `debian/linaro-rootfs.img` (new step in `scripts/rootfs/build.sh`), so the
  vendor `firmware`/`updateimg` packaging uses the appliance rootfs.
- **Image** (`make image` → `make image-manifest`): vendor `firmware` +
  `updateimg` succeeded; artifacts collected into `dist/`
  (`boot.img`, `rootfs.img` ~4.99G, `uboot.img`, `MiniLoaderAll.bin`,
  `parameter.txt`, `update.img`, `tspi-rk3566-user-v10-linux.dtb`,
  `MANIFEST.txt`, `SHA256SUMS`).
- **Verification**: `make rootfs-verify` → PASS; `make verify` → PASS.
  Confirmed in `dist/rootfs.img` via `debugfs`: `kvm` in `/etc/passwd` and in the
  `sudo` group, `one-kvm.service` enabled, hostname `taishankvm`.

### Container-specific fixes added this phase (each committed)

- `scripts/rootfs/build.sh`: create vendor `check-debian.sh` markers
  (live-build/debootstrap `bookworm`) at runtime; mount `binfmt_misc` +
  `update-binfmts --enable qemu-aarch64`; add a passwd entry for the SDK owner
  uid so the vendor `sudo -u '#<uid>'` (kernel-helper) resolves; realign
  `external/rkwifibt` ownership to `RK_OWNER_UID`; repack the customized rootfs.
  Added `ROOTFS_CUSTOMIZE_ONLY=1` (make target `rootfs-customize`) to re-run only
  the customization + repack.
- `scripts/kernel/configure.sh`: auto-detect the SDK prebuilt
  `aarch64-none-linux-gnu-` toolchain.
- `scripts/rootfs/customize.sh`: actually call `chroot_setup`; robust
  `create_user` (reuse the existing `kvm` group, de-duplicate, edit `/etc/group`
  directly for supplementary groups, direct-write fallback for the account).
- `builder/Dockerfile`: live-build/debootstrap `bookworm` markers.

### NEXT

1. Flash manually per `docs/FLASHING.md` (assistant does not touch block
   devices). Prefer `dist/update.img` with `RKDevTool` / `upgrade_tool`.
2. On the board: `sudo bash scripts/verify/target-smoke.sh` to check SSH, `wlan0`,
   `/sys/class/udc`, UVC capture, and One-KVM service; confirm ADB is not holding
   the UDC.
3. Set real Wi-Fi / recovery-AP passphrases in `config/local.env` (current values
   look like placeholders) and rebuild if a custom-network image is desired.

> Note: an earlier `docs/STATUS.md` revision contained a build path whose
> username matched the configured PSK, tripping the secrets scan. The value was
> redacted; rotate the Wi-Fi/recovery PSKs if this tree is ever pushed.

