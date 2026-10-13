#!/usr/bin/env bash
# scripts/sdk/inspect.sh
# Detect the SDK state and inspect the vendor tree. Never hard-codes the
# 20260807 internal layout; it probes for markers and reports what it finds.
# Writes build/sdk-inspection.txt. Exits 0 in state A (with guidance).
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

REPORT="${BUILD_DIR}/sdk-inspection.txt"
CHIP="${SDK_CHIP_DIRNAME:-rk3566_rk3568}"

emit() { printf '%s\n' "$*" | tee -a "${REPORT}" >&2; }

inspect_synced_tree() {
  local w="$1" k
  emit ""
  emit "## Vendor tree inspection"
  emit "work tree: ${w}"

  local chip_dir="${w}/device/rockchip/.chips/${CHIP}"
  emit ""
  emit "### Board defconfigs (device/rockchip/.chips/${CHIP}/)"
  if [[ -d "${chip_dir}" ]]; then
    find "${chip_dir}" -maxdepth 1 -name '*_defconfig' -printf '  %f\n' 2>/dev/null | sort | tee -a "${REPORT}" >&2 || true
  else
    emit "  (chip dir not found; globbing device/rockchip for *_defconfig)"
    find "${w}/device/rockchip" -maxdepth 3 -name '*_defconfig' -printf '  %p\n' 2>/dev/null | sort | tee -a "${REPORT}" >&2 || true
  fi

  emit ""
  emit "### Kernel tree"
  k="$(sdk_kernel_tree || true)"
  if [[ -n "${k}" ]]; then
    emit "  ${k}"
    local ver
    ver="$(sed -n 's/^VERSION = //p;' "${k}/Makefile" 2>/dev/null | head -1)"
    local plevel
    plevel="$(sed -n 's/^PATCHLEVEL = //p;' "${k}/Makefile" 2>/dev/null | head -1)"
    [[ -n "${ver}" ]] && emit "  kernel version: ${ver}.${plevel:-?}"
    emit "  DTS candidates (arch/arm64/boot/dts/rockchip/tspi-rk3566*):"
    find "${k}/arch/arm64/boot/dts/rockchip" -maxdepth 1 -name 'tspi-rk3566*' -printf '    %f\n' 2>/dev/null | sort | tee -a "${REPORT}" >&2 || true
  else
    emit "  not detected"
  fi

  emit ""
  emit "### DWC3 / USB controller nodes in the board DTS"
  if [[ -n "${k}" ]]; then
    grep -rnE '(usbdrd_dwc3|usb_host0_xhci|dr_mode)' \
      "${k}/arch/arm64/boot/dts/rockchip"/tspi-rk3566* 2>/dev/null | head -40 | tee -a "${REPORT}" >&2 || true
  fi

  emit ""
  emit "### Rootfs / packaging entrypoints"
  local p
  for p in debian ubuntu buildroot device/rockchip/common/scripts build.sh; do
    [[ -e "${w}/${p}" ]] && emit "  present: ${p}" || emit "  absent:  ${p}"
  done

  emit ""
  emit "### Output layout"
  for p in output output/firmware output/rockchip_* rockdev; do
    [[ -e "${w}/${p}" ]] && emit "  present: ${p}" || true
  done
}

inspect_main() {
  ensure_build_dirs
  : >"${REPORT}"
  {
    printf '# SDK inspection report\n'
    printf '# generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# project git: %s\n' "$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    printf '# expected SDK: %s\n' "${SDK_NAME:-unknown}"
  } >>"${REPORT}"

  local state
  state="$(sdk_detect_state)"
  emit "SDK state: $(sdk_state_label "${state}")"
  emit ""
  emit "## Markers"
  sdk_markers | tee -a "${REPORT}" >&2

  case "${state}" in
    A)
      emit ""
      emit "## Action required (State A)"
      emit "Place the SDK at: ${SDK_VENDOR_DIR}/${SDK_VENDOR_DIRNAME:-tspi_1m_linux_kernel6.1_sdk_20260807}"
      emit "Then run: make sdk-check && make sdk-extract && make sdk-sync"
      ;;
    B|C|D|E)
      local w
      w="$(sdk_find_work_dir || sdk_find_vendor_dir || true)"
      [[ -n "${w}" ]] && inspect_synced_tree "${w}"
      ;;
  esac

  emit ""
  log_info "inspection written to ${REPORT#${PROJECT_ROOT}/}"
}

inspect_main
