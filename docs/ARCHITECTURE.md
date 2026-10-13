# Architecture

This document explains how the TaishanPi RK3566 One-KVM appliance is put
together: what runs on the build host, what runs on the board, where the vendor
BSP ends and our code begins, and how the build pipeline maps onto the Make
targets and scripts in this repository.

`AGENTS.md` is the authoritative contract. If this document and `AGENTS.md`
disagree, `AGENTS.md` wins.

---

## 1. Two machines, two jobs

The project deliberately separates the machine that builds the image from the
machine that runs it.

| | Build host | Target (TaishanPi) |
|---|---|---|
| Role | Compile kernel, assemble rootfs, package images | Run the KVM appliance |
| OS | Ubuntu 22.04 (inside Docker) | Minimal Debian ARM64 |
| Container runtime | Docker or Podman, required | **None, ever** |
| Kernel | Host kernel, irrelevant | Vendor Rockchip Linux 6.1 |
| Output | `dist/` artifacts | Flashed eMMC |

Docker exists only on the development host. It provides a disposable Ubuntu
22.04 sandbox with the vendor Kernel 6.1 build dependencies. The multi-gigabyte
SDK is bind-mounted into that sandbox, never copied into the image. The target
rootfs must not contain Docker, containerd, or any other container runtime
unless the user explicitly changes the requirement.

The reason is simple. A KVM appliance needs a small, predictable, recoverable
system. A container runtime on the target adds attack surface, boot complexity,
and a second way for the USB gadget stack to be owned by the wrong process.

---

## 2. The vendor BSP boundary

The bottom of the stack is the Rockchip/LCKFB vendor BSP from the SDK
`tspi_1m_linux_kernel6.1_sdk_20260807`:

- vendor U-Boot;
- vendor Linux 6.1 kernel tree;
- vendor device trees and board support;
- vendor Wi-Fi firmware and module integration (AP6212);
- vendor boot image layout and Rockchip packaging.

We do not replace the vendor kernel with Debian generic or mainline. Vendor
board support, DT bindings, and packaging are the stable foundation for V1.
Modernizing the kernel for elegance is explicitly out of scope.

Our changes to the BSP are small and reproducible:

1. A device-tree patch that forces the Type-C DWC3 controller to
   `dr_mode = "peripheral"`.
2. A kernel configuration fragment that enables the USB gadget, ConfigFS, and
   UVC/V4L2 capabilities the appliance needs.

Both live under `patches/kernel/` and `config/kernel-required.config`, and both
are applied idempotently. The active board DTS path is **detected** from the
SDK by `scripts/kernel/detect-board.sh`, not hard-coded from older tutorials.

The exact DTS/DTSI filename, the board lunch/config target, and the kernel tree
path are all SDK-dependent. Scripts detect them and report what they find. This
document describes the mechanism, not a fixed filename.

---

## 3. The Debian userspace boundary

Above the kernel sits a minimal Debian ARM64 userspace. "Minimal" here means
small and understood, not hand-rolled.

The starting point is the SDK-supported Debian/rootfs build path. That path
already carries the board integration we would otherwise have to reconstruct:
firmware, kernel modules, udev rules, boot scripts, users and groups, and board
initialization. We preserve it, then minimize on top of it.

We do not jump to an independent `debootstrap --variant=minbase` rootfs unless
the SDK integration has first been mapped and every required piece is preserved
and tested. Replacing the vendor rootfs wholesale is a last resort, not a
starting move.

Minimization happens through two explicit, reviewable inputs:

- `config/packages-target.txt` lists the packages the appliance needs.
- `rootfs-overlay/` holds files merged into the target rootfs (systemd units,
  SSH policy, NetworkManager configuration, helper scripts).

Packages that are explicitly excluded from production: Docker, containerd,
snapd, cloud-init, desktop environments, X11, Wayland, GUI stacks, and large
compiler toolchains. Build dependencies stay on the build host.

---

## 4. One-KVM native runtime

One-KVM is the Rust implementation, installed natively as an ARM64 package. It
is pinned in `config/versions.env` and staged under the gitignored `downloads/`
directory. The install path prefers the official ARM64 `.deb` and its own
systemd unit, adding only minimal drop-ins where needed.

One-KVM owns the USB Device Controller at runtime. It manages the gadget
through Linux ConfigFS and exposes keyboard, relative mouse, absolute mouse
where supported, and virtual media (USB mass storage). Optional USB Ethernet
(NCM/ECM/RNDIS) is available only if it does not complicate V1.

There is no Docker on the target, so there is no container boundary between
One-KVM and the kernel. The service talks to ConfigFS and the UDC directly.

---

## 5. USB topology

The board has two USB roles, and they must not be confused.

- **Type-C** is the Rockchip DWC3 controller. It is forced to
  `dr_mode = "peripheral"` so the board acts as a USB device toward the managed
  computer. This is the path that carries HID and virtual media.
- **Type-A** is a USB host port. It carries the UVC HDMI capture card.

The managed computer sees the TaishanPi as a keyboard, mouse, and mass-storage
device. The TaishanPi sees the managed computer's HDMI output through the
capture card on Type-A.

ADB is disabled by default and must never contend with One-KVM for the UDC. If
ADB debug support is retained, it is opt-in and mutually exclusive: stop
One-KVM, unbind its gadget, start ADB, and reverse the sequence when disabling.
Two owners of one UDC is never a valid state.

Physical wiring, VBUS isolation, and the Y-cable are covered in
[`HARDWARE.md`](HARDWARE.md).

---

## 6. Network topology

The primary network is the onboard AP6212 Wi-Fi, managed by NetworkManager.

- Station mode joins the configured network and gets DHCP.
- mDNS/Avahi publishes the appliance as `taishankvm.local` by default.
- OpenSSH is enabled at boot and is the primary maintenance channel. It does
  not depend on ADB.
- If station mode is unavailable, an optional recovery AP starts after a
  configurable timeout (default proposal 60 seconds) at `192.168.66.1/24`.
- UART is the last-resort console for Wi-Fi, SSH, boot, or gadget failure.

Wi-Fi credentials come from the gitignored `config/local.env` and are injected
at build time. They are never committed and never written to logs.

---

## 7. System block diagram

```text
                        BUILD HOST (Ubuntu 22.04 + Docker)
   +------------------------------------------------------------------+
   |  builder/Dockerfile  ->  taishanpi-kvm-builder:22.04             |
   |  repo bind-mounted at /work (SDK never COPY'd into the image)    |
   |                                                                  |
   |  scripts/host   scripts/sdk   scripts/kernel                     |
   |  scripts/rootfs scripts/image scripts/verify                     |
   +---------------------------------+--------------------------------+
                                     |
                                     | produces
                                     v
   +------------------------------------------------------------------+
   |  dist/  boot.img  rootfs.img  uboot.img  MiniLoaderAll.bin       |
   |         parameter.txt  update.img  *.dtb                         |
   |         MANIFEST.txt  SHA256SUMS                                 |
   +---------------------------------+--------------------------------+
                                     |
                                     | manual flash (never automatic)
                                     v
                        TARGET (TaishanPi RK3566)
   +------------------------------------------------------------------+
   |  Vendor U-Boot  ->  Vendor Linux 6.1  ->  Minimal Debian ARM64   |
   |                                                                  |
   |  One-KVM (Rust, native systemd)   NetworkManager   OpenSSH       |
   |        |                                |              |         |
   |        | ConfigFS gadget                | wlan0        | sshd    |
   |        v                                v              v         |
   |   Type-C DWC3 (peripheral)        AP6212 Wi-Fi     LAN / AP     |
   |        |                                                         |
   |        | USB HID + mass storage                                  |
   |        v                                                         |
   |   Managed computer  <---- HDMI ---->  Type-A host                |
   |                                        UVC capture card          |
   +------------------------------------------------------------------+
```

---

## 8. Data and control flows

**Control path (KVM input).** The operator opens the One-KVM Web UI over the
network. One-KVM translates input events into USB HID reports and writes them
to the ConfigFS gadget. The DWC3 controller in peripheral mode presents those
reports to the managed computer as a standard keyboard and mouse.

**Video path (capture).** The managed computer's HDMI output goes to the UVC
capture card on Type-A. The vendor kernel's UVC/V4L2 stack exposes it as a
`/dev/videoN` device. One-KVM reads the stream and serves it to the Web UI.

**Virtual media path.** One-KVM exposes an image as a USB mass-storage LUN
through the same ConfigFS gadget. The managed computer sees a removable drive.

**Management path.** SSH over Wi-Fi is the normal maintenance channel. UART is
the fallback when the network or boot is broken.

**Build path.** The host drives the pipeline through Make targets. In-builder
targets are wrapped by `scripts/host/enter-builder.sh`, so a privileged
container is used implicitly. The pipeline ends with artifacts in `dist/` and a
manifest. Flashing is a separate, manual, explicit step.

---

## 9. Pipeline phases mapped to targets and scripts

The Makefile is the discoverable interface. Host-side targets run directly.
In-builder targets run through `scripts/host/enter-builder.sh --`.

| Phase | Make target | Script | Runs on | Purpose |
|---|---|---|---|---|
| Host check | `make doctor` | `scripts/host/doctor.sh` | host | Validate docker, git, SDK presence, config |
| Builder image | `make builder` | `scripts/host/build-builder.sh` | host | Build the Ubuntu 22.04 sandbox |
| Builder shell | `make shell` | `scripts/host/enter-builder.sh` | host | Interactive privileged shell |
| SDK detect | `make sdk-check` | `scripts/sdk/inspect.sh` | host | Detect state A..E and inspect the tree |
| SDK extract | `make sdk-extract` | `scripts/sdk/extract.sh` | builder | Idempotent vendor extraction |
| SDK sync | `make sdk-sync` | `scripts/sdk/sync.sh` | builder | Idempotent local `.repo` sync |
| Baseline | `make baseline` | `scripts/sdk/baseline-build.sh` | builder | Smallest unmodified vendor build |
| Board detect | `make kernel-detect` | `scripts/kernel/detect-board.sh` | host | Find active DTS and DWC3 node |
| Patch | `make patch` | `scripts/kernel/patch.sh` | builder | Apply DWC3 peripheral patch |
| Kernel config | `make kernel-configure` | `scripts/kernel/configure.sh` | builder | Apply required config fragment |
| Kernel build | `make kernel` | `scripts/kernel/build.sh` + `verify.sh` | builder | Build and verify effective config/DTB |
| Kernel verify | `make kernel-verify` | `scripts/kernel/verify.sh` | builder | Re-check `.config` and DTB mode |
| Rootfs | `make rootfs` | `scripts/rootfs/build.sh` | builder | Build and customize the rootfs |
| Rootfs verify | `make rootfs-verify` | `scripts/rootfs/verify.sh` | host | Check SSH, NetworkManager, One-KVM, no Docker |
| Image | `make image` | `scripts/image/build.sh` | builder | Package vendor images |
| Manifest | `make image-manifest` | `scripts/image/manifest.sh` | host | Write `MANIFEST.txt` and `SHA256SUMS` |
| Static verify | `make verify` | `scripts/verify/static.sh` | host | Run all host/static gates |
| Target smoke | `make target-smoke` | `scripts/verify/target-smoke.sh` | target | On-device checks (copied to the board) |
| Full pipeline | `make all` | Makefile | host | doctor, builder, sdk-check, then the build chain |

`make all` stops with guidance when the SDK is absent (State A). It does not
pretend to build.

---

## 10. Component responsibilities

| Component | Location | Responsibility |
|---|---|---|
| Builder image | `builder/Dockerfile` | Ubuntu 22.04 sandbox with vendor build deps; Python 3 default |
| Builder entrypoint | `builder/entrypoint.sh` | Prepare the sandbox environment on start |
| Host scripts | `scripts/host/` | Doctor, build the image, enter the sandbox |
| SDK scripts | `scripts/sdk/` | Detect, extract, sync, baseline-build the vendor SDK |
| Kernel scripts | `scripts/kernel/` | Detect board, patch DWC3, configure, build, verify |
| Rootfs scripts | `scripts/rootfs/` | Build, customize, install One-KVM, verify the rootfs |
| Image scripts | `scripts/image/` | Package vendor images, collect artifacts, write manifest |
| Verify scripts | `scripts/verify/` | Static host gates and the on-device smoke test |
| Shared library | `scripts/lib/common.sh` | Strict mode, paths, logging, env loading, redaction |
| SDK state library | `scripts/lib/sdk.sh` | SDK location and state detection (A..E) |
| Kernel patches | `patches/kernel/` | Reproducible, idempotent device-tree patches |
| Rootfs overlay | `rootfs-overlay/` | Files merged into the target rootfs |
| Target packages | `config/packages-target.txt` | Explicit package baseline |
| Required kernel config | `config/kernel-required.config` | Symbols checked in the effective `.config` |
| Versions | `config/versions.env` | Pinned SDK, One-KVM, and builder versions |
| Secrets | `config/local.env` | Gitignored Wi-Fi, SSH, recovery AP values |
| SDK intake | `sdk/vendor/` | Downloaded multi-part SDK (gitignored) |
| SDK work tree | `sdk/work/` | Extracted and synced tree (gitignored) |
| Deliverables | `dist/` | Final artifacts, manifest, checksums |

---

## 11. Design principles

The choices above follow a small set of rules, restated from `AGENTS.md`
section 22:

- Reproducibility over cleverness.
- Explicit scripts over undocumented shell history.
- Native systemd integration over target-side containers.
- Vendor BSP stability over unnecessary kernel modernization.
- Minimal, understood package sets over aggressive deletion.
- SSH and UART recovery over ADB dependence.
- Verified effective configuration over source-file assumptions.
- Small, reviewable patches over direct mass edits.

Any deviation from these rules must be documented with the concrete technical
reason.
