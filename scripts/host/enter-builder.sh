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
if [[ -d /proc/sys/fs/binfmt_misc ]]; then
  run_args+=(-v /proc/sys/fs/binfmt_misc:/proc/sys/fs/binfmt_misc)
else
  log_warn "/proc/sys/fs/binfmt_misc not present; qemu-user-static chroot may not work"
fi

if [[ "${1:-}" == "--" ]]; then
  shift
  [[ "$#" -gt 0 ]] || die "enter-builder.sh -- requires a command"
  log_phase "Running in builder: $*"
  exec "${engine}" "${run_args[@]}" "${image_ref}" "$@"
fi

log_phase "Entering interactive builder shell (${image_ref})"
exec "${engine}" "${run_args[@]}" -it "${image_ref}"
