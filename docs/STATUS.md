# Implementation Status

Last updated: 2026-09-22. Repository initialization complete; build phases are
SDK-gated (State A).

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
`/home/dingxiaoyu/orca/workspaces/tspi/init/sdk/vendor/tspi_1m_linux_kernel6.1_sdk_20260807/`

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

1. `make baseline` — prove the unmodified vendor toolchain. **Blocked on Docker**:
   the daemon is not running in this environment (no `/var/run/docker.sock`, no
   systemd), so run it host-side or start `dockerd` first.
2. `make patch && make kernel`.
3. `make rootfs && make image`.

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
- Performed host-side because the builder container is unavailable; the Makefile
  targets `sdk-extract`/`sdk-sync` wrap through `scripts/host/enter-builder.sh`.

#### BLOCKED (environment) — `make baseline`

- Board config is ready: `rockchip_rk3566_taishanpi_1m_v10_defconfig` is detected
  under `device/rockchip/.chips/rk3566_rk3568/`, and `build.sh` is present.
- Cannot build yet: the builder container is unavailable and cannot be started by
  the agent — Docker daemon is down (`/var/run/docker.sock` absent), there is no
  systemd, no passwordless `sudo`, `/var/run` is not writable, and `podman` is not
  installed.
- Host-side build is not viable either: required toolchain pieces are missing
  (`flex`, `dtc`, `bc`, …) and cannot be installed without root.
- Resolution: start a working Docker daemon (or provide a host with the vendor
  build dependencies / a privileged builder) and re-run `make baseline`.

### Notes on removed tooling

All ad-hoc download tooling created during this phase was removed at the user's
request after the SDK was received and verified: the reusable
`scripts/sdk/download.sh` + `scripts/sdk/download_manifest.py`, the `curl`
resolve-retry loop, the generated wget script, and all manifests/logs/partial
shards. No signed URLs remain anywhere in the repository. `build/` now contains
only `build-builder.log` and `sdk-inspection.txt`.

