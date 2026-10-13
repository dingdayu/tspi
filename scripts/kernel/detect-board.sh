#!/usr/bin/env bash
# scripts/kernel/detect-board.sh
# Detect the active TaishanPi board DTS/DTSI and its USB DWC3 node(s).
# Host-runnable. Writes build/kernel-detection.txt.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

REPORT="${BUILD_DIR}/kernel-detection.txt"
DTS_REL="arch/arm64/boot/dts/rockchip"

emit() { printf '%s\n' "$*" | tee -a "${REPORT}" >&2; }

detect_main() {
  ensure_build_dirs
  : >"${REPORT}"
  {
    printf '# kernel/device-tree detection\n'
    printf '# generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >>"${REPORT}"

  log_phase "Kernel / board DTS detection"

  local kernel
  if ! kernel="$(sdk_kernel_tree)"; then
    emit "SDK/kernel tree not detected. Place the SDK and run 'make sdk-sync'."
    log_info "report: ${REPORT#${PROJECT_ROOT}/}"
    return 0
  fi
  emit "kernel tree: ${kernel}"

  local dts_dir="${kernel}/${DTS_REL}"
  if [[ ! -d "${dts_dir}" ]]; then
    emit "DTS dir not found: ${dts_dir}"
    die "cannot find ${DTS_REL} in the kernel tree"
  fi

  emit ""
  emit "## Board DTS/DTSI candidates (tspi-rk3566*)"
  local -a dts_files=()
  mapfile -t dts_files < <(find "${dts_dir}" -maxdepth 1 -name 'tspi-rk3566*' -print 2>/dev/null | sort)
  if [[ ${#dts_files[@]} -eq 0 ]]; then
    emit "  none found; dumping rk3566* candidates instead"
    mapfile -t dts_files < <(find "${dts_dir}" -maxdepth 1 -name 'rk3566*tspi*' -print 2>/dev/null | sort)
  fi
  local f
  for f in "${dts_files[@]}"; do emit "  $(basename "${f}")"; done

  # Top-level board DTS candidates (ones that are not .dtsi).
  local -a board_dts=()
  for f in "${dts_files[@]}"; do
    [[ "${f}" == *.dts ]] && board_dts+=("${f}")
  done
  if [[ ${#board_dts[@]} -eq 0 ]]; then
    emit ""
    emit "no top-level .dts candidate found; patch.sh will require an explicit BOARD_DTS"
  else
    emit ""
    emit "## Selected board DTS candidate: $(basename "${board_dts[0]}")"
    emit "BOARD_DTS=${board_dts[0]}"
  fi

  emit ""
  emit "## DWC3 / USB controller nodes"
  local pat='usbdrd_dwc3|usb_host0_xhci|dr_mode'
  grep -rnE "${pat}" "${kernel}/${DTS_REL}" 2>/dev/null \
    | grep -E 'tspi-rk3566|rk3568\.dtsi|rk3566\.dtsi' \
    | head -60 | tee -a "${REPORT}" >&2 || emit "  (no matches)"

  emit ""
  log_info "report: ${REPORT#${PROJECT_ROOT}/}"
}

detect_main
