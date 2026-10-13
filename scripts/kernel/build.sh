#!/usr/bin/env bash
# scripts/kernel/build.sh
# Build the vendor kernel + DTB using the SDK build.sh. Override the
# subcommand with KERNEL_BUILD_CMD (default: kernel).
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/kernel-build.log"

build_main() {
  log_phase "Kernel build"
  ensure_build_dirs
  require_cmd bash

  local state
  state="$(sdk_detect_state)"
  case "${state}" in
    A) sdk_require_present ;;
    B|C) die "SDK not ready (state ${state}). Run 'make sdk-sync' and 'make baseline'." ;;
  esac

  local work build_sh
  work="$(sdk_find_work_dir)" || die "cannot locate the SDK work tree"
  build_sh="${work}/build.sh"
  require_file "${build_sh}"

  if [[ -n "${KERNEL_BUILD_CMD:-}" ]]; then
    log_info "using KERNEL_BUILD_CMD: ${KERNEL_BUILD_CMD}"
    ( cd "${work}" && run_logged "${LOG_FILE}" bash -c "${KERNEL_BUILD_CMD}" )
  else
    log_phase "vendor build.sh kernel"
    ( cd "${work}" && run_logged "${LOG_FILE}" bash "${build_sh}" kernel )
  fi

  log_info "kernel build finished; log: ${LOG_FILE#${PROJECT_ROOT}/}"
}

build_main
