# patches/kernel

Reproducible kernel/device-tree patches applied to the vendor SDK work tree.

## Rules (AGENTS.md sections 3.1 and 12)

- Patch **only** the TaishanPi RK3566 board path, never every Rockchip board.
- Every patch must be applicable idempotently (`git apply --check` first, skip
  if already applied).
- Name patches `NNNN-short-description.patch`.
- The active board DTS path is DETECTED by `scripts/kernel/detect-board.sh`,
  not hard-coded from older tutorials.

## Primary patch: Type-C DWC3 peripheral mode

The TaishanPi Type-C USB controller must resolve to:

```dts
&usbdrd_dwc3 {
    dr_mode = "peripheral";
};
```

`scripts/kernel/patch.sh` locates the active DWC3 node in the selected board
DTS/DTSI and applies the change. The concrete patch is generated once the SDK
is present (State B+); until then only the detection/apply machinery is
committed.
