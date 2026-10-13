#!/usr/bin/env bash
# scripts/kernel/patch.sh
# Force the TaishanPi Type-C DWC3 controller to dr_mode = "peripheral".
# Idempotent; touches only the selected board DTS and records a reproducible
# patch under patches/kernel/.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/kernel-patch.log"
DTS_REL="arch/arm64/boot/dts/rockchip"
MARKER="taishanpi-kvm: Type-C DWC3 forced to peripheral mode"
NODE="${DWC3_NODE:-usbdrd_dwc3}"

# Choose the board DTS: explicit BOARD_DTS, else the first tspi-rk3566*.dts.
select_board_dts() {
  local kernel="$1"
  local dir="${kernel}/${DTS_REL}"
  if [[ -n "${BOARD_DTS:-}" ]]; then
    [[ -f "${BOARD_DTS}" ]] && { printf '%s' "${BOARD_DTS}"; return 0; }
    [[ -f "${dir}/${BOARD_DTS}" ]] && { printf '%s' "${dir}/${BOARD_DTS}"; return 0; }
    return 1
  fi
  find "${dir}" -maxdepth 1 -name 'tspi-rk3566*.dts' -print 2>/dev/null | sort | head -1
}

patch_main() {
  log_phase "Kernel patch: ${NODE} -> peripheral"
  ensure_build_dirs
  require_cmd bash grep sed

  local kernel
  kernel="$(sdk_kernel_tree)" || die "kernel tree not found; run 'make sdk-sync' first"

  local dts
  dts="$(select_board_dts "${kernel}")" || true
  if [[ -z "${dts}" ]]; then
    die "no TaishanPi board DTS found (looked for tspi-rk3566*.dts under ${DTS_REL}). Set BOARD_DTS explicitly."
  fi
  log_info "target DTS: ${dts#${PROJECT_ROOT}/}"

  if grep -qF "${MARKER}" "${dts}"; then
    log_info "patch already applied (marker present); skipping"
  else
    if ! grep -qE "&${NODE}[[:space:]]*\{" "${kernel}/${DTS_REL}"/*.dts* 2>/dev/null; then
      log_warn "node &${NODE} was not found in the board DTS/I; verify the label (AGENTS.md section 3.1)"
    fi
    log_info "appending peripheral-mode override to board DTS"
    {
      printf '\n/* %s */\n' "${MARKER}"
      printf '&%s {\n\tdr_mode = "peripheral";\n};\n' "${NODE}"
    } >>"${dts}"
  fi

  # Record a reproducible patch when the work tree is a git checkout.
  if git -C "${kernel}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local rel="${dts#${kernel}/}"
    local out="${PATCHES_DIR}/kernel/0001-tspi-dwc3-peripheral.patch"
    if git -C "${kernel}" diff -- "${rel}" >"${out}" 2>/dev/null && [[ -s "${out}" ]]; then
      log_info "patch recorded: ${out#${PROJECT_ROOT}/}"
    else
      rm -f "${out}"
      log_warn "could not record a git diff for ${rel}; the DTS edit is still applied"
    fi
  fi

  # Confirm the effective value in the board DTS now resolves to peripheral.
  if grep -A3 -E "&${NODE}[[:space:]]*\{" "${dts}" | grep -q 'dr_mode = "peripheral"'; then
    log_info "verified: &${NODE} dr_mode = peripheral in board DTS"
  else
    log_warn "override appended but could not confirm 'dr_mode = \"peripheral\"' inline; check the DTB after build"
  fi
  log_info "log: ${LOG_FILE#${PROJECT_ROOT}/}"
}

run_logged "${LOG_FILE}" patch_main
