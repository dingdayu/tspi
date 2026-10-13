# Builder container

Ubuntu 22.04 sandbox with the LCKFB TaishanPi Kernel 6.1 SDK build
dependencies. **Docker is used on the development host only** — never on the
TaishanPi target (AGENTS.md sections 2.1 and 11).

## Build the image

```bash
make builder          # or: scripts/host/build-builder.sh
```

## Enter the sandbox

```bash
make shell            # interactive, privileged
```

Equivalent raw command (for reference):

```bash
docker run --privileged -it --rm \
  -v "$(pwd)":/work -w /work \
  -v /proc/sys/fs/binfmt_misc:/proc/sys/fs/binfmt_misc \
  taishanpi-kvm-builder:22.04
```

`--privileged` and the `binfmt_misc` mount are needed for vendor
rootfs/chroot/qemu-user-static operations.

## Run a single command inside the sandbox

```bash
scripts/host/enter-builder.sh -- scripts/kernel/build.sh
```

## Design notes

- The multi-GB SDK is bind-mounted, never `COPY`'d into the image.
- Default `python` is **Python 3** (`python-is-python3`). Legacy vendor scripts
  that need Python 2 must call `python2.7` explicitly.
- A non-root `builder` user has passwordless sudo, for vendor scripts that need
  both user and root steps.
- `ENABLE_CCACHE=1` at build time adds ccache; correctness never depends on it.
