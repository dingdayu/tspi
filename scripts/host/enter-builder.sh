#!/usr/bin/env bash
# scripts/host/enter-builder.sh
# Enter the privileged builder container.
#   enter-builder.sh              interactive shell
#   enter-builder.sh -- <cmd..>   run a command, propagate its exit code
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
load_env

engine="$(require_container_engine)"
image_ref="${BUILDER_IMAGE_REF:-taishanpi-kvm-builder:22.04}"

if ! "${engine}" image inspect "${image_ref}" >/dev/null 2>&1; then
  log_info "builder image ${image_ref} not found; building it first"
  bash "${SCRIPTS_DIR}/host/build-builder.sh"
fi

run_args=(run --privileged --rm
  -v "${PROJECT_ROOT}:/work"
  -w /work
  -e "RK_SDK_DIR=/work/sdk")
# Share the host binfmt_misc registry only when it is a real mountpoint. A plain
# directory under /proc cannot be bind-mounted (Docker errors with "cannot be
# mounted because it is inside /proc"), and qemu-aarch64 may not be registered.
if mountpoint -q /proc/sys/fs/binfmt_misc; then
  run_args+=(-v /proc/sys/fs/binfmt_misc:/proc/sys/fs/binfmt_misc)
else
  log_warn "/proc/sys/fs/binfmt_misc is not a mountpoint; skipping the bind mount."
  log_warn "For arm64 chroot (Debian rootfs) enable it on the host:"
  log_warn "  sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc"
  log_warn "  sudo update-binfmts --enable qemu-aarch64"
fi

if [[ "${1:-}" == "--" ]]; then
  shift
  [[ "$#" -gt 0 ]] || die "enter-builder.sh -- requires a command"
  log_phase "Running in builder: $*"
  exec "${engine}" "${run_args[@]}" "${image_ref}" "$@"
fi

log_phase "Entering interactive builder shell (${image_ref})"
exec "${engine}" "${run_args[@]}" -it "${image_ref}"
