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

run_args=(run --privileged --rm -i
  -v "${PROJECT_ROOT}:/work"
  -w /work)
# Attach stdin (-i) so vendor interactive prompts (e.g. check-network.sh's
# "Enter any thing within 5 seconds") can be answered. Forward host proxy
# settings so the vendor network probes and Buildroot downloads can reach the
# internet from inside the container.
for v in http_proxy https_proxy ftp_proxy all_proxy no_proxy \
         HTTP_PROXY HTTPS_PROXY NO_PROXY; do
  [[ -n "${!v:-}" ]] && run_args+=(-e "${v}")
done
# NOTE: do NOT pass RK_* variables (e.g. RK_SDK_DIR) via -e. The vendor
# device/rockchip/common/scripts/build.sh flags externally-set RK_* vars as
# "custom environments" and blocks on an interactive `read -t 10`, which fails
# in a non-TTY run. The SDK auto-detects its own paths.
# binfmt_misc is intentionally NOT bind-mounted by default: newer runc rejects
# mounting /proc/sys/fs/binfmt_misc into a container ("cannot be mounted because
# it is inside /proc"). Register the arm64 interpreter on the HOST instead:
#   docker run --privileged --rm tonistiigi/binfmt --install arm64
# Set BUILDER_MOUNT_BINFMT=1 to opt back in (only if your runtime allows it).
if [[ "${BUILDER_MOUNT_BINFMT:-0}" == "1" ]]; then
  if mountpoint -q /proc/sys/fs/binfmt_misc; then
    run_args+=(-v /proc/sys/fs/binfmt_misc:/proc/sys/fs/binfmt_misc)
    log_info "binding host binfmt_misc into the builder (BUILDER_MOUNT_BINFMT=1)"
  else
    log_warn "BUILDER_MOUNT_BINFMT=1 but /proc/sys/fs/binfmt_misc is not a mountpoint; skipping"
  fi
fi

if [[ "${1:-}" == "--" ]]; then
  shift
  [[ "$#" -gt 0 ]] || die "enter-builder.sh -- requires a command"
  # The repo is bind-mounted at /work, but callers (e.g. the Makefile) pass host
  # absolute paths. Rewrite any argument under PROJECT_ROOT to its /work path.
  map_path() { local a="$1"; printf '%s' "${a/#${PROJECT_ROOT}/\/work}"; }
  cmd=()
  for a in "$@"; do cmd+=("$(map_path "$a")"); done
  log_phase "Running in builder: ${cmd[*]}"
  exec "${engine}" "${run_args[@]}" "${image_ref}" "${cmd[@]}"
fi

log_phase "Entering interactive builder shell (${image_ref})"
exec "${engine}" "${run_args[@]}" -it "${image_ref}"
