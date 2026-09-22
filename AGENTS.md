# AGENTS.md — TaishanPi RK3566 One-KVM Appliance

## 0. Purpose

This repository builds a reproducible IP-KVM appliance image for the LCKFB TaishanPi / 泰山派 RK3566 using the vendor Linux 6.1 SDK.

The target is not a general-purpose ARM server. It is a maintainable KVM appliance with:

- Rockchip/LCKFB vendor U-Boot and Linux 6.1 board support.
- Minimal Debian ARM64 userspace built through the vendor-supported SDK path where possible.
- One-KVM Rust installed natively on the target; **no Docker/container runtime on the TaishanPi**.
- Type-C DWC3 forced to USB peripheral/device mode for HID and virtual media.
- Type-A used as USB Host for a UVC HDMI capture card.
- Board Wi-Fi (AP6212) as the primary network.
- OpenSSH enabled at boot as the primary maintenance channel.
- UART as the emergency/recovery console.
- ADB disabled by default and never allowed to contend with One-KVM for the USB Device Controller.
- Optional Wi-Fi recovery AP when the configured station network is unavailable.

This file is the project contract for humans and coding agents. Preserve these architecture decisions unless the user explicitly changes them.

---

## 1. Hardware target

Primary target:

- Board: LCKFB TaishanPi / 泰山派, RK3566, 1M/2G+16G class board.
- Target SDK: `tspi_1m_linux_kernel6.1_sdk_20260807`.
- CPU architecture: ARM64 / aarch64.
- Target storage: eMMC, approximately 16 GB.
- Target RAM: approximately 2 GB.
- USB Device port: board Type-C / Rockchip DWC3.
- USB Host port: board Type-A.
- Video: generic UVC HDMI capture card such as MS2109/MS2130 class devices.
- Network: onboard AP6212 Wi-Fi.
- Maintenance: SSH over Wi-Fi; UART fallback.

Expected physical topology:

```text
                         +---- 5V power source
                         |
TaishanPi Type-C -- Y ----+---- USB data to managed/target computer
                         |     D+/D-/GND only on target-computer branch
                         |     VBUS from target-computer branch MUST be isolated
                         |
TaishanPi Type-A -------- UVC HDMI capture dongle
                              ^
                              |
Managed computer HDMI --------+

TaishanPi AP6212 Wi-Fi ------ LAN / recovery AP
```

Safety requirement:

- The Y-cable branch connected to the managed computer must not back-feed VBUS into the TaishanPi power path.
- Ground must remain common and USB D+/D- must remain connected.
- Do not invent wiring assumptions. Document the exact wiring in `docs/HARDWARE.md`.

---

## 2. Architecture decisions

### 2.1 Build host

Use Docker only on the development/build host.

Baseline builder:

- Ubuntu 22.04.
- Docker/Podman-compatible Dockerfile is acceptable, but Docker commands are the documented default.
- Container may require `--privileged` for vendor rootfs/chroot/binfmt/mount workflows.
- Project directory is bind-mounted into the builder.
- SDK and build output are not copied into the Docker image.
- Default `python` must resolve to Python 3.
- Python 2.7 may be installed only for legacy vendor scripts and must be invoked explicitly.

Never install Docker, containerd, or a container runtime in the production TaishanPi rootfs unless the user explicitly changes this requirement.

### 2.2 Kernel and bootloader

Use the Rockchip/LCKFB vendor U-Boot and vendor Linux 6.1 tree from the 20260807 SDK for V1.

Do not replace the vendor kernel with Debian generic/mainline solely for elegance.

Preserve vendor board support, Wi-Fi firmware/module integration, DT bindings, boot image layout, and Rockchip packaging.

### 2.3 Target userspace

V1 target userspace is **Minimal Debian ARM64**, but "Minimal Debian" means:

- Start from the SDK-supported Debian/rootfs build path where practical.
- Preserve vendor board integration.
- Minimize the installed userspace with an explicit package manifest and rootfs overlay.
- Do not replace the vendor-supported rootfs with a hand-rolled `debootstrap --variant=minbase` unless the SDK integration has first been mapped and all required firmware, kernel modules, boot scripts, users/groups, udev rules, and board initialization are preserved and tested.

The goal is a minimal server/appliance userspace, not a BusyBox-only embedded distribution.

### 2.4 One-KVM

Use current One-KVM Rust, ARM64, installed natively.

Preferred installation:

- Pin an explicit One-KVM release/version in `config/versions.env`.
- Obtain the official ARM64 `.deb` when available.
- Cache or stage the package under a gitignored download/cache directory.
- Install it into the target rootfs.
- Create/enable a native systemd service as required by the package/project.

Do not deploy One-KVM through Docker on the target.

Do not use the obsolete Python One-KVM implementation unless the user explicitly requests it.

### 2.5 Networking

Primary network:

- `NetworkManager`
- `wpa_supplicant` or the backend selected by NetworkManager
- onboard `wlan0`
- DHCP by default
- optional mDNS/Avahi name, default proposal: `taishankvm.local`

Provisioning rules:

- Never commit real Wi-Fi credentials.
- Provide `config/local.env.example`.
- Real secrets belong in `config/local.env`, which must be gitignored.
- Allow build-time injection of SSID/PSK for a private image.
- If no valid station connection is available, support an optional recovery hotspot after a configurable timeout (default proposal: 60 seconds).
- Recovery AP defaults should be documented and configurable; do not ship a universal hard-coded public password in source control.

### 2.6 SSH

SSH is a first-class requirement.

Production image must:

- install `openssh-server`;
- enable `ssh.service`/`sshd` at boot;
- start SSH without any dependency on ADB;
- allow maintenance over Wi-Fi;
- disable direct root SSH login;
- prefer public-key authentication;
- support explicit development-mode password authentication if configured locally.

Recommended user:

- `kvm` or `kvmadmin`;
- member of `sudo` and any required video/input/device groups;
- exact choice must be documented and kept consistent.

A production build should fail or loudly warn if neither an SSH public key nor an explicitly approved password-auth development mode is configured.

### 2.7 ADB

ADB is not the normal management channel.

Rules:

- ADB must be disabled/masked by default.
- No boot-time Rockchip ADB USB gadget may bind the DWC3 UDC.
- One-KVM owns the USB Gadget path during normal operation.
- If the vendor rootfs contains `adbd`, it may be retained for development/recovery only.
- Optional `adb-debug-enable`/`adb-debug-disable` tooling may be implemented.
- ADB debug mode must be mutually exclusive with One-KVM USB Gadget:
  1. stop One-KVM;
  2. unbind/clean the current gadget;
  3. start/bind ADB;
  4. reverse the sequence when disabling ADB.

Never try to make ADB and One-KVM concurrently own the same UDC.

### 2.8 UART

Document UART as the last-resort console for:

- Wi-Fi failure;
- SSH failure;
- boot failure;
- USB Gadget failure.

Do not remove the vendor serial console until the appliance is stable and the user explicitly requests hardening.

---

## 3. Required kernel/device-tree capabilities

The final kernel configuration must be verified from the **effective generated `.config`**, not merely from a defconfig fragment.

Required or expected capabilities include:

```text
CONFIG_USB_GADGET
CONFIG_USB_CONFIGFS
CONFIG_USB_CONFIGFS_F_HID
CONFIG_USB_CONFIGFS_MASS_STORAGE
CONFIG_USB_CONFIGFS_NCM
CONFIG_USB_CONFIGFS_ECM
CONFIG_USB_CONFIGFS_RNDIS        # if supported/desired
CONFIG_TUN

CONFIG_MEDIA_SUPPORT
CONFIG_VIDEO_DEV
CONFIG_MEDIA_USB_SUPPORT
CONFIG_USB_VIDEO_CLASS
CONFIG_SND_USB_AUDIO             # useful for capture devices exposing USB audio
```

Built-in (`=y`) is preferred for appliance-critical USB Gadget pieces unless the vendor build has a proven module-loading path.

Do not blindly append symbols and assume success. After the kernel configuration step, verify every required symbol in the effective `.config` and report deviations.

### 3.1 USB DWC3 device mode

The Type-C DWC3 node must resolve to:

```dts
dr_mode = "peripheral";
```

The actual DTS/DTSI filename must be detected from the 20260807 SDK rather than assumed.

Likely candidates may resemble:

```text
kernel-6.1/arch/arm64/boot/dts/rockchip/tspi-rk3566-*.dts*
```

Agent workflow:

1. Search the SDK for `usbdrd_dwc3`.
2. Determine which board DTS/DTSI is actually included by the selected TaishanPi defconfig/board config.
3. Patch only the relevant board file.
4. Store a reproducible patch under `patches/kernel/`.
5. Make patch application idempotent.
6. Verify the built DTB contains the intended effective mode.

Do not patch every Rockchip board globally.

---

## 4. Video capture requirements

Target a generic UVC HDMI capture card.

Production validation must cover:

```bash
lsusb
ls -l /dev/video*
v4l2-ctl --list-devices
v4l2-ctl -d /dev/video0 --list-formats-ext
```

Initial recommended operating point:

- MJPEG where supported;
- 1920x1080;
- 30 FPS.

Do not make 1080p60 a hard requirement for V1.

The exact `/dev/videoN` number must not be assumed forever. Where practical, create a stable udev-based alias or discover the intended device by attributes.

---

## 5. USB Gadget / One-KVM requirements

Normal runtime expects One-KVM to manage the gadget through Linux ConfigFS.

Required user-visible KVM functions:

- keyboard;
- relative mouse;
- absolute mouse where supported;
- virtual media / USB mass-storage;
- optional USB Ethernet (ECM/NCM/RNDIS) only if it does not complicate V1.

Before One-KVM starts:

- `libcomposite` must be available/loaded as required;
- `/sys/class/udc/` must expose the Rockchip DWC3 UDC;
- no vendor ADB gadget may already own it.

Do not use an ad-hoc HID test descriptor copied from unverified tutorials. If a manual HID smoke-test is added, use a valid Linux HID gadget descriptor and document its protocol/subclass/report length.

---

## 6. Target package baseline

Keep the package list explicit and reviewable.

Expected baseline includes, subject to actual Debian package names in the SDK:

```text
systemd
systemd-timesyncd

openssh-server
sudo

network-manager
wpasupplicant
iw
rfkill
wireless-regdb
avahi-daemon

iproute2
iputils-ping
ethtool
dnsutils

kmod
usbutils
v4l-utils

ca-certificates
curl
wget

bash-completion
less
vim-tiny or vim
nano

python3

lsof
strace
rsync
tmux
htop
```

Optional packages must be justified.

Explicitly exclude from the production image unless a concrete need appears:

```text
docker
docker.io
containerd
snapd
cloud-init
desktop environments
X11
Wayland
GUI stacks
large compiler toolchains
build-essential
full development headers
```

Keep build dependencies on the build host, not on the appliance.

---

## 7. Repository layout

Converge toward this structure unless the existing repository already has a compatible organization:

```text
.
├── AGENTS.md
├── README.md
├── Makefile
├── .gitignore
├── .dockerignore
│
├── builder/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── README.md
│
├── config/
│   ├── versions.env
│   ├── build.env.example
│   ├── local.env.example
│   ├── packages-target.txt
│   └── kernel-required.config
│
├── patches/
│   └── kernel/
│       └── README.md
│
├── rootfs-overlay/
│   ├── etc/
│   │   ├── modules-load.d/
│   │   ├── systemd/system/
│   │   ├── ssh/
│   │   └── NetworkManager/
│   └── usr/local/sbin/
│
├── scripts/
│   ├── lib/
│   │   ├── common.sh
│   │   └── sdk.sh
│   ├── host/
│   │   ├── doctor.sh
│   │   ├── build-builder.sh
│   │   └── enter-builder.sh
│   ├── sdk/
│   │   ├── inspect.sh
│   │   ├── extract.sh
│   │   ├── sync.sh
│   │   └── baseline-build.sh
│   ├── kernel/
│   │   ├── detect-board.sh
│   │   ├── patch.sh
│   │   ├── configure.sh
│   │   ├── build.sh
│   │   └── verify.sh
│   ├── rootfs/
│   │   ├── build.sh
│   │   ├── customize.sh
│   │   ├── install-one-kvm.sh
│   │   └── verify.sh
│   ├── image/
│   │   ├── build.sh
│   │   ├── collect.sh
│   │   └── manifest.sh
│   └── verify/
│       ├── static.sh
│       └── target-smoke.sh
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── BUILD.md
│   ├── HARDWARE.md
│   ├── NETWORK.md
│   ├── RECOVERY.md
│   ├── FLASHING.md
│   ├── VALIDATION.md
│   └── STATUS.md
│
├── sdk/
│   ├── README.md
│   ├── vendor/             # downloaded multi-part SDK folder, gitignored
│   └── work/               # extracted/synced SDK tree, gitignored
│
├── downloads/              # One-KVM .deb and other caches, gitignored
├── build/                  # temporary build state, gitignored
└── dist/                   # final deliverables, gitignored or selectively published
```

Do not reorganize destructively if the repository already contains user work. Migrate incrementally.

---

## 8. Git and destructive-operation rules

Before broad changes:

1. inspect the repository;
2. read existing docs and scripts;
3. run `git status --short`;
4. preserve user modifications.

Never run without explicit user approval:

```text
git reset --hard
git clean -fd
git checkout .
git restore .
git stash
```

Do not delete unknown files merely because they do not match this proposed structure.

Do not commit SDK source trees, SDK archives, credentials, generated rootfs images, large build outputs, or private keys.

Expected `.gitignore` coverage includes:

```text
config/local.env
sdk/vendor/
sdk/work/
downloads/
build/
dist/*.img
dist/*.bin
dist/*.deb
*.log
.cache/
```

Keep small manifests/checksums/documentation in Git where useful.

---

## 9. Reproducibility requirements

All important manual steps must eventually become scripts or documented Make targets.

Desired top-level interface:

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

Exact target names may be adjusted if the existing project has a better convention, but maintain a similarly discoverable interface.

Scripts must:

- use `set -Eeuo pipefail`;
- be idempotent where feasible;
- print clear phase headers;
- fail with actionable messages;
- never silently continue after a critical failure;
- never guess the SDK location if multiple candidates are present;
- support paths containing spaces where reasonable;
- record relevant versions and Git SHAs in the final manifest;
- keep secrets out of logs.

---

## 10. SDK lifecycle

The user will place the downloaded folder similar to:

```text
tspi_1m_linux_kernel6.1_sdk_20260807/
```

under the project's SDK intake location.

The project must support these states:

### State A — SDK absent

Prepare the entire repository and builder, then stop the SDK build phase with a precise message stating:

- expected placement path;
- expected folder name;
- next command.

Do not ask the user to repeat information already encoded here.

### State B — downloaded multi-part SDK present

Detect `extract_sdk.sh`, validate expected files, and expose an idempotent extraction target.

### State C — extracted SDK with `.repo` only or incomplete worktree

Use the vendor-provided repo tooling and local objects where appropriate, e.g. the actual supported equivalent of:

```bash
.repo/repo/repo sync -l -j"$(nproc)"
```

Do not substitute a network-heavy repo sync if the SDK is specifically packaged for local sync unless necessary.

### State D — fully synced SDK

Run SDK introspection before patching:

- identify board lunch/config targets;
- identify selected kernel tree;
- identify selected board DTS/DTSI;
- identify Debian/rootfs build entrypoints;
- identify image packaging entrypoints;
- identify boot partition/image layout.

Persist findings in `docs/STATUS.md` and/or a generated `build/sdk-inspection.txt`.

### State E — baseline build

Before modifying kernel or rootfs, perform the smallest practical vendor baseline build needed to prove the unmodified SDK toolchain works.

Do not mix "vendor SDK is broken" with "our patches are broken".

---

## 11. Builder image requirements

The builder Dockerfile should begin from Ubuntu 22.04 and include the vendor-documented Kernel 6.1 build dependencies plus tools needed by our scripts.

Important rules:

- Default `python` -> Python 3.
- Python 2.7 installed only if required by real SDK scripts.
- Include cross-build/aarch64 tool support when needed.
- Include `repo`, `git`, `rsync`, `qemu-user-static`, `binfmt-support`, `device-tree-compiler`, `bison`, `flex`, ncurses headers, SSL headers, LZ4 tooling, `fakeroot`, `cmake`, `gcc-multilib`, `g++-multilib`, and other dependencies found in the vendor documentation/SDK.
- Prefer a non-root `builder` user with passwordless sudo inside the disposable build container if vendor scripts need both user and root steps.
- Document that the container is a build sandbox and may need `--privileged`.
- Bind-mount the repo; do not `COPY` the SDK into the image.
- Allow optional ccache without making correctness depend on it.

Before finalizing the dependency list, inspect the 20260807 SDK and update it from actual errors or vendor scripts rather than perpetuating stale package lists.

---

## 12. Kernel modification workflow

Never hand-edit the vendor SDK without preserving a reproducible patch.

Expected sequence:

1. inspect selected board config;
2. build/validate baseline if feasible;
3. locate active DWC3 board node;
4. create patch for `dr_mode = "peripheral"`;
5. create a kernel config fragment or scripted config update;
6. apply changes idempotently;
7. build;
8. verify effective `.config`;
9. decompile/inspect built DTB when practical;
10. collect kernel/DTB/boot artifacts.

If a required symbol is renamed or unavailable in the 20260807 kernel, investigate the vendor Kconfig and document the equivalent instead of forcing a nonexistent symbol.

---

## 13. Rootfs customization workflow

Preserve the vendor Debian integration first, then minimize.

Expected steps:

1. build vendor-supported Debian rootfs;
2. inspect its package set and board-specific additions;
3. identify firmware/modules/udev/systemd pieces required by:
   - AP6212 Wi-Fi;
   - DWC3;
   - UVC;
   - storage/eMMC;
   - board-specific initialization;
4. apply `packages-target.txt`;
5. remove only clearly unnecessary general-purpose packages;
6. apply `rootfs-overlay/`;
7. install/pin One-KVM ARM64 package;
8. enable NetworkManager;
9. enable SSH;
10. disable/mask vendor ADB gadget startup;
11. load `libcomposite` as required;
12. configure hostname/mDNS;
13. configure log rotation/journald limits appropriate for eMMC;
14. verify no target Docker/container runtime is installed;
15. produce a package manifest.

Do not aggressively purge vendor packages until their purpose is understood.

---

## 14. SSH and account provisioning

Implement a reproducible account policy.

Recommended defaults:

```text
hostname: taishankvm
user: kvm
root SSH login: disabled
SSH service: enabled
public-key auth: enabled
password auth: development-only/configurable
```

Provide an example local configuration, e.g.:

```text
SSH_PUBLIC_KEY_FILE=~/.ssh/id_ed25519.pub
ALLOW_PASSWORD_SSH=0
TARGET_USERNAME=kvm
TARGET_HOSTNAME=taishankvm
```

Do not store a private key in the repository or image build context.

---

## 15. Wi-Fi provisioning and recovery

Implement two modes:

### Normal station mode

Configuration source:

- `config/local.env`, or
- a build-time secret/injection mechanism.

Example variable names:

```text
WIFI_SSID=
WIFI_PSK=
WIFI_COUNTRY=
```

Never echo `WIFI_PSK` to logs.

### Recovery AP

If enabled:

- wait for normal station connectivity for a configurable interval;
- if unavailable, start a NetworkManager hotspot;
- use a predictable local address, proposal `192.168.66.1/24`;
- expose SSH and One-KVM locally;
- stop/reconfigure the hotspot automatically when normal station mode is restored if that behavior proves reliable.

Document the exact operational behavior in `docs/NETWORK.md`.

Keep recovery AP logic simple. Reliability is more important than a captive portal.

---

## 16. One-KVM service integration

The agent must inspect the actual current One-KVM Rust package/release layout before writing final service commands.

Requirements:

- native ARM64 install;
- version pinned;
- service enabled at boot;
- data/config location documented;
- logs available through systemd/journald;
- service ordering compatible with required kernel filesystems/modules;
- no dependency on Docker.

If the official `.deb` ships a service, prefer it and add minimal drop-ins rather than replacing it unnecessarily.

If systemd unit changes are needed, put them in `rootfs-overlay/etc/systemd/system/...` and document why.

---

## 17. Build outputs

Collect final artifacts under `dist/`.

At minimum preserve all artifacts needed to reproduce or flash the device, based on the actual vendor layout, potentially including:

```text
boot.img
rootfs.img
uboot.img
MiniLoaderAll.bin
parameter.txt
update.img
*.dtb
```

Do not assume every item exists; inspect the SDK.

Generate:

```text
dist/MANIFEST.txt
dist/SHA256SUMS
```

Manifest should include:

- build timestamp;
- SDK name/date;
- SDK/repo manifest revision when available;
- kernel version and commit;
- effective board config;
- One-KVM version;
- target package manifest hash;
- hashes of final artifacts.

---

## 18. Validation gates

A build is not "done" merely because compilation exits 0.

### 18.1 Host/static validation

Check:

- builder image builds;
- shell scripts syntax passes;
- required project files exist;
- no secrets are tracked;
- SDK inspection succeeds;
- kernel effective config contains required symbols;
- patched DTS/DTB resolves to peripheral mode;
- target rootfs contains SSH and NetworkManager;
- SSH is enabled;
- One-KVM is installed and enabled;
- vendor ADB gadget service is disabled/masked;
- target rootfs has no Docker/containerd unless explicitly requested;
- final artifact hashes exist.

### 18.2 Target smoke test

Provide `scripts/verify/target-smoke.sh` that can be copied/run on a booted TaishanPi and checks, without destructive changes:

```text
uname -a
systemctl is-enabled ssh
systemctl is-active ssh
systemctl is-active NetworkManager
ip link show wlan0
nmcli device status
ls /sys/class/udc
mount | grep configfs
ls /sys/kernel/config/usb_gadget
lsusb
v4l2-ctl --list-devices
systemctl status one-kvm
journalctl -u one-kvm
```

It should clearly distinguish:

- kernel/UDC failure;
- ADB/gadget ownership conflict;
- video capture failure;
- Wi-Fi failure;
- One-KVM service failure.

### 18.3 Functional acceptance

Final hardware acceptance criteria:

1. TaishanPi cold-boots without keyboard/display.
2. Board joins configured Wi-Fi or enters documented recovery AP mode.
3. SSH is reachable.
4. `wlan0` is stable.
5. UDC appears in `/sys/class/udc/`.
6. UVC capture card appears and streams.
7. One-KVM Web UI is reachable.
8. Managed PC recognizes keyboard/mouse gadget.
9. Keyboard works in BIOS/UEFI where the managed PC permits standard USB HID.
10. Relative/absolute mouse works as configured.
11. Virtual media can be exposed and detached.
12. Reboot returns to the same healthy state.
13. ADB is not occupying UDC in normal mode.

---

## 19. Flashing safety

Build tooling may prepare flashing commands and documentation.

Do **not** automatically flash the board, write raw block devices, repartition the host, or invoke destructive Rockchip flashing commands unless the user explicitly requests that action in the active session.

`docs/FLASHING.md` must document:

- Loader mode;
- MaskRom recovery;
- exact artifacts;
- backup/recovery considerations;
- how to identify the correct Rockchip device.

Prefer a manual explicit final flashing step.

---

## 20. Documentation requirements

Keep these current as implementation proceeds:

### `README.md`

Quick project overview and happy-path commands.

### `docs/ARCHITECTURE.md`

Explain:

- build host vs target;
- vendor BSP boundary;
- Debian userspace boundary;
- One-KVM native runtime;
- USB and network topology.

### `docs/BUILD.md`

Exact reproducible build workflow from empty repo + downloaded SDK to final artifacts.

### `docs/HARDWARE.md`

Y-cable, UVC capture, Type-C/Type-A roles, VBUS safety.

### `docs/NETWORK.md`

Normal Wi-Fi, recovery AP, mDNS, SSH.

### `docs/RECOVERY.md`

UART, ADB debug mode if implemented, MaskRom, network recovery.

### `docs/FLASHING.md`

Explicit manual flashing procedure.

### `docs/VALIDATION.md`

All static and target tests.

### `docs/STATUS.md`

Continuously updated implementation status:

```text
DONE
IN PROGRESS
BLOCKED
NEXT
```

Include concrete filenames/commands and avoid vague prose.

---

## 21. Agent execution method

When a coding agent starts in this repository:

1. Read this file completely.
2. Inspect existing repository files.
3. Run `git status --short`.
4. Do not assume the proposed layout is absent or safe to overwrite.
5. Detect whether the SDK is present.
6. Create/update `docs/STATUS.md`.
7. Make the smallest coherent implementation changes needed for the current phase.
8. Run validation after each phase.
9. Fix failures when the cause is inside this repository.
10. Record external blockers precisely.
11. Continue automatically to the next safe phase if prerequisites are satisfied.
12. Do not stop merely to ask for confirmation when the next action is non-destructive and clearly implied by this contract.
13. Do stop before hardware flashing or destructive block-device operations unless explicitly authorized.

When the SDK is absent, complete all repository scaffolding, builder preparation, scripts that can be written safely, and documentation. Then provide the exact SDK placement path and next command.

When the SDK is present, inspect the real 20260807 tree and adapt the implementation to reality. Do not blindly trust stale path names from older tutorials.

---

## 22. Quality bar

Prefer:

- reproducibility over cleverness;
- explicit scripts over undocumented shell history;
- native systemd integration over target-side containers;
- vendor BSP stability over unnecessary kernel modernization;
- minimal, understood package sets over aggressive deletion;
- SSH/UART recovery over ADB dependence;
- verified effective configuration over source-file assumptions;
- small, reviewable patches over direct mass edits.

Any major deviation from these principles must be documented with the concrete technical reason.

---

## 23. Reference sources

Use these as baseline references, but always inspect the actual SDK and current upstream project before hard-coding behavior:

- LCKFB TaishanPi Kernel 6.1 build documentation:
  `https://wiki.lckfb.com/zh-hans/tspi-rk3566/sdk-compilation/kernel6-1-linux-compilation.html`
- LCKFB TaishanPi documentation:
  `https://wiki.lckfb.com/zh-hans/tspi-rk3566/`
- One-KVM documentation:
  `https://docs.one-kvm.cn/`
- One-KVM source:
  `https://github.com/mofeng-git/One-KVM`

The target SDK version for this project is:

```text
tspi_1m_linux_kernel6.1_sdk_20260807
```

If current upstream documentation conflicts with older tutorials, verify the actual SDK behavior and document the resolution rather than silently choosing one.
