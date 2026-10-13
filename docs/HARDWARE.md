# Hardware

This document describes the physical setup for the TaishanPi RK3566 One-KVM
appliance: the board, the Y-cable, the USB roles, the UVC capture card, and the
VBUS safety rule that keeps the board from being back-fed.

`AGENTS.md` section 1 is the authoritative source for the topology. This
document expands it and marks every detail that depends on the user's actual
cable as a TODO to confirm.

---

## 1. Board

| Item | Value |
|---|---|
| Board | LCKFB TaishanPi / 泰山派 |
| SoC | Rockchip RK3566 |
| Class | 1M / 2G RAM + 16G eMMC |
| Storage | eMMC, approximately 16 GB |
| RAM | approximately 2 GB |
| USB device port | Type-C, Rockchip DWC3 |
| USB host port | Type-A |
| Network | onboard AP6212 Wi-Fi |
| Maintenance | SSH over Wi-Fi, UART fallback |

The board is not a general-purpose server. It is a KVM appliance that presents
itself to a managed computer as a keyboard, mouse, and removable drive, while
capturing that computer's HDMI output.

---

## 2. USB roles

The two USB ports have fixed, opposite roles. Do not swap them.

| Port | Role | Direction | Carries |
|---|---|---|---|
| Type-C | USB device / peripheral | TaishanPi to managed computer | HID keyboard, mouse, virtual media |
| Type-A | USB host | Managed computer to TaishanPi | UVC HDMI capture stream |

Type-C runs the Rockchip DWC3 controller. The device tree is patched so this
controller resolves to:

```dts
&usbdrd_dwc3 {
    dr_mode = "peripheral";
};
```

The active board DTS path is detected from the SDK by
`scripts/kernel/detect-board.sh`. The patch is applied by `make patch` and
verified by `make kernel`. See [`BUILD.md`](BUILD.md) for the build steps.

Type-A is a normal host port. The UVC capture card plugs in here and appears to
the kernel as a V4L2 video device.

---

## 3. Y-cable topology

The Type-C port must both power the board and carry USB data to the managed
computer. A Y-cable splits those two functions.

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

Reading the diagram:

- One branch of the Y goes to a 5V power source. This is what powers the board.
- The other branch goes to the managed computer and carries USB data only.
- The managed computer's HDMI output goes to the capture card on Type-A.
- Wi-Fi connects the board to the LAN or to the recovery AP.

---

## 4. VBUS isolation (safety critical)

The branch of the Y-cable that connects to the managed computer must not
back-feed VBUS into the TaishanPi power path.

Why this matters: if the managed computer's 5V VBUS reaches the board's power
input while the board is also powered from its own 5V source, the two supplies
fight. That can damage the board, the managed computer's USB port, or both. It
can also confuse the DWC3 controller's role detection.

The rule:

- The target-computer branch carries **D+, D-, and GND only**.
- VBUS on that branch must be isolated, either by a cable that does not connect
  VBUS, or by a data-only adapter, or by a VBUS-blocking element.
- Ground must remain common across all branches.
- D+ and D- must remain connected to the managed computer.

Do not rely on the managed computer's port to power the board. Power the board
from its own 5V source.

TODO (confirm with your cable): the exact isolation method depends on the
Y-cable you buy or build. Record whether VBUS is physically absent, blocked by
a diode, or blocked by a data-only adapter. See the checklist in section 8.

---

## 5. Ground and data lines

| Line | Requirement |
|---|---|
| GND | Common across power source, TaishanPi, and managed computer |
| D+ | Connected between TaishanPi Type-C and managed computer |
| D- | Connected between TaishanPi Type-C and managed computer |
| VBUS (target branch) | Isolated, must not reach the TaishanPi power path |

A common ground is required for USB signaling to work. Without it, the data
lines have no reference and enumeration fails or becomes unreliable.

---

## 6. UVC HDMI capture card

The capture card is a generic UVC device, MS2109 or MS2130 class. It plugs into
Type-A and presents the managed computer's HDMI output to the kernel as a V4L2
video device.

Recommended operating point for V1:

- MJPEG where the card supports it;
- 1920x1080;
- 30 FPS.

1080p60 is not a hard requirement for V1. Do not design around it.

The exact `/dev/videoN` number is not stable across boots or card models. Do
not hard-code it. Where practical, create a stable udev alias or discover the
device by its attributes.

Validation commands, run on the target:

```bash
lsusb
ls -l /dev/video*
v4l2-ctl --list-devices
v4l2-ctl -d /dev/video0 --list-formats-ext
```

Notes on card classes:

- MS2109 class cards are common and inexpensive. They often expose MJPEG and
  YUYV. Confirm the actual formats with `v4l2-ctl --list-formats-ext`.
- MS2130 class cards are newer and often support higher frame rates. Treat the
  advertised specs as claims to verify, not facts.
- Some cards expose USB audio as well. `CONFIG_SND_USB_AUDIO` is enabled for
  that case.

TODO (confirm with your card): record the exact chipset, the USB vendor and
product IDs from `lsusb`, and the formats and frame rates the card actually
reports.

---

## 7. Do not invent wiring

Do not assume a wiring detail that has not been measured or read from the
cable's documentation. A wrong assumption about VBUS isolation can damage
hardware. A wrong assumption about D+/D- can waste hours on enumeration
failures that look like software bugs.

If a detail is unknown, mark it as unknown and confirm it before powering the
managed computer. The build tooling cannot detect your cable. Only you can.

---

## 8. Wiring record checklist

Fill this in for your actual setup. Keep it with the appliance.

| Item | Value | Confirmed? |
|---|---|---|
| Y-cable model / part number | TODO | TODO |
| Y-cable source (vendor, DIY) | TODO | TODO |
| VBUS isolation method on target branch | TODO (absent / diode / data-only adapter) | TODO |
| Power source rating (5V, amps) | TODO | TODO |
| GND common across all branches | TODO | TODO |
| D+ connected to managed computer | TODO | TODO |
| D- connected to managed computer | TODO | TODO |
| Capture card chipset | TODO | TODO |
| Capture card USB VID:PID | TODO | TODO |
| Capture card max format / FPS | TODO | TODO |
| Managed computer USB port type | TODO | TODO |

Once the wiring is confirmed, replace the TODOs above with the real values and
remove the TODO markers. Until then, treat every TODO row as unverified.

---

## 9. Physical acceptance checks

These map to the functional acceptance criteria in `AGENTS.md` section 18.3.
They are performed on real hardware, not in the build pipeline.

1. The board cold-boots with no keyboard or display attached.
2. The board joins the configured Wi-Fi, or enters the documented recovery AP.
3. SSH is reachable over the network.
4. `wlan0` is stable.
5. The UDC appears in `/sys/class/udc/`.
6. The UVC capture card appears and streams.
7. The One-KVM Web UI is reachable.
8. The managed computer recognizes the keyboard and mouse gadget.
9. The keyboard works in BIOS/UEFI where the managed computer permits standard
   USB HID.
10. Relative and absolute mouse work as configured.
11. Virtual media can be exposed and detached.
12. A reboot returns the board to the same healthy state.
13. ADB is not occupying the UDC in normal mode.

The on-device smoke test that supports these checks is
`scripts/verify/target-smoke.sh`, run via `make target-smoke` for instructions.
See [`VALIDATION.md`](VALIDATION.md) for the full test matrix.

---

## 10. Related documents

- [`ARCHITECTURE.md`](ARCHITECTURE.md) for the system boundaries and USB roles.
- [`BUILD.md`](BUILD.md) for building the image that runs on this hardware.
- [`FLASHING.md`](FLASHING.md) for the manual flashing procedure.
- [`RECOVERY.md`](RECOVERY.md) for UART, ADB debug, and MaskRom recovery.
