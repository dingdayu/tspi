#!/usr/bin/env bash
# scripts/kernel/configure.sh
# Apply config/kernel-required.config to the vendor kernel using the tree's
# scripts/config, then resolve dependencies with olddefconfig. Idempotent.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/kernel-configure.log"
REQ_FILE="${CONFIG_DIR}/kernel-required.config"
KERNEL_CFG="${RK_KERNEL_CFG:-rockchip_linux_defconfig}"

# Use the SDK's prebuilt aarch64 toolchain when available. The vendor tree ships
# `aarch64-none-linux-gnu-gcc`, not the Debian-style `aarch64-linux-gnu-gcc`, so
# the old default broke `make olddefconfig` ("C compiler ... not found").
detect_cross_compile() {
  local w tc
  w="$(sdk_find_work_dir 2>/dev/null || true)"
  [[ -n "${w}" ]] || return 1
  tc="$(find "${w}/prebuilts/gcc/linux-x86/aarch64" -maxdepth 3 \
        -name 'aarch64-none-linux-gnu-gcc' -print -quit 2>/dev/null || true)"
  [[ -n "${tc}" ]] || return 1
  printf '%s' "${tc%-gcc}-"
}
if [[ -z "${CROSS_COMPILE:-}" ]]; then
  CROSS_COMPILE="$(detect_cross_compile || true)"
fi
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

apply_one() {
  local tree="$1" sym="$2" val="$3" warnc=0
  case "${val}" in
    y) "${tree}/scripts/config" --file "${tree}/.config" --enable "${sym}" || { log_warn "cannot enable ${sym}"; warnc=$((warnc + 1)); } ;;
    m) "${tree}/scripts/config" --file "${tree}/.config" --module "${sym}" || { log_warn "cannot set ${sym}=m"; warnc=$((warnc + 1)); } ;;
    *) log_warn "unsupported value '${val}' for ${sym}; skipping"; warnc=$((warnc + 1)) ;;
  esac
  return "${warnc}"
}

configure_main() {
  log_phase "Kernel configuration (required symbols)"
  ensure_build_dirs
  require_cmd bash
  require_file "${REQ_FILE}"

  local kernel
  kernel="$(sdk_kernel_tree)" || die "kernel tree not found; run 'make sdk-sync' first"
  [[ -x "${kernel}/scripts/config" ]] || die "missing ${kernel#${PROJECT_ROOT}/}/scripts/config"

  if [[ ! -f "${kernel}/.config" ]]; then
    log_info "no .config yet; generating from ${KERNEL_CFG}"
    ( cd "${kernel}" && run_logged "${LOG_FILE}" make ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE}" "${KERNEL_CFG}" )
  fi

  local sym val warnings=0
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "${line}" | tr -d '[:space:]')"
    [[ -z "${line}" ]] && continue
    if [[ "${line}" == *=* ]]; then
      sym="${line%%=*}"; val="${line#*=}"
    else
      sym="${line}"; val="y"
    fi
    apply_one "${kernel}" "${sym}" "${val}" || warnings=$((warnings + 1))
  done <"${REQ_FILE}"

  log_phase "Resolving dependencies (olddefconfig)"
  ( cd "${kernel}" && run_logged "${LOG_FILE}" make ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig )

  if [[ "${warnings}" -gt 0 ]]; then
    log_warn "${warnings} symbol(s) could not be set; 'make kernel-verify' will report deviations"
  fi
  log_info "configuration applied; log: ${LOG_FILE#${PROJECT_ROOT}/}"
}

configure_main
