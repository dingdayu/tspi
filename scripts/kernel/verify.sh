#!/usr/bin/env bash
# scripts/kernel/verify.sh
# Authoritative kernel gate: check every required symbol in the EFFECTIVE
# .config, and confirm the built DTB sets DWC3 dr_mode = "peripheral".
#   --allow-missing  exit 0 instead of non-zero when the tree is not built yet
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

REPORT="${BUILD_DIR}/kernel-verify.txt"
REQ_FILE="${CONFIG_DIR}/kernel-required.config"
DTS_REL="arch/arm64/boot/dts/rockchip"
DWC3_NODE="${DWC3_NODE:-usbdrd_dwc3}"
ALLOW_MISSING=0
for arg in "$@"; do
  [[ "${arg}" == "--allow-missing" ]] && ALLOW_MISSING=1
done

missing=0
emit() { printf '%s\n' "$*" | tee -a "${REPORT}" >&2; }

check_config() {
  local kernel="$1" cfg="${kernel}/.config"
  emit ""
  emit "## Effective .config symbol check (${cfg#${PROJECT_ROOT}/})"
  local sym want have line
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "${line}" | tr -d '[:space:]')"
    [[ -z "${line}" ]] && continue
    if [[ "${line}" == *=* ]]; then sym="${line%%=*}"; want="${line#*=}"; else sym="${line}"; want="y"; fi
    have="$(grep -E "^${sym}=" "${cfg}" 2>/dev/null | head -1 | cut -d= -f2 || true)"
    if [[ "${have}" == "${want}" ]]; then
      emit "  OK      ${sym}=${have}"
    else
      emit "  MISSING ${sym} (want=${want}, got=${have:-unset})"
      missing=$((missing + 1))
    fi
  done <"${REQ_FILE}"
}

check_dtb() {
  local kernel="$1" dts_name dtb
  dts_name="$(grep -oP 'RK_KERNEL_DTS_NAME="\K[^"]+' "$(sdk_find_work_dir 2>/dev/null)/output/.config" 2>/dev/null || true)"
  [[ -n "${dts_name}" ]] || dts_name="$(basename "$(find "${kernel}/${DTS_REL}" -maxdepth 1 -name 'tspi-rk3566*.dts' -print -quit 2>/dev/null)" .dts)"
  dtb="$(find "${kernel}" -name "${dts_name}.dtb" -print -quit 2>/dev/null || true)"
  emit ""
  emit "## DTB DWC3 mode check (dts=${dts_name:-unknown})"
  if [[ -z "${dtb}" ]]; then
    emit "  no built .dtb found for ${dts_name:-the board}; rebuild with 'make kernel'"
    return 1
  fi
  if ! command -v dtc >/dev/null 2>&1; then
    emit "  dtc not installed; cannot decompile ${dtb#${PROJECT_ROOT}/}"
    return 1
  fi
  # `dtc -I dtb -O dts` does not inline labels, so the node appears as its unit
  # address (e.g. usb@fcc00000) and the label only in __symbols__. Resolve the
  # label to a node path and read dr_mode directly from the DTB with fdtget.
  local dts_txt node_path leaf val node
  dts_txt="$(dtc -I dtb -O dts -o - "${dtb}" 2>/dev/null || true)"
  node_path="$(printf '%s\n' "${dts_txt}" | sed -n "s/.*[[:space:]]${DWC3_NODE} = \"\([^\"]*\)\";.*/\1/p" | head -1)"
  if [[ -n "${node_path}" ]] && command -v fdtget >/dev/null 2>&1; then
    val="$(fdtget -t s "${dtb}" "${node_path}" dr_mode 2>/dev/null || true)"
    if [[ "${val}" == "peripheral" ]]; then
      emit "  OK      &${DWC3_NODE} (${node_path}) dr_mode = \"peripheral\""
      return 0
    fi
    emit "  note    &${DWC3_NODE} at ${node_path} has dr_mode=${val:-unset}"
  fi
  # Fallback: locate the node text by its leaf name (or any snps,dwc3 node).
  if [[ -n "${node_path}" ]]; then
    leaf="${node_path##*/}"
    node="$(printf '%s\n' "${dts_txt}" | grep -A40 -E "^[[:space:]]*${leaf} \{" | head -60 || true)"
  fi
  [[ -n "${node}" ]] || node="$(printf '%s\n' "${dts_txt}" | grep -A30 'compatible = "snps,dwc3"' | head -60 || true)"
  if printf '%s' "${node}" | grep -q 'dr_mode = "peripheral"'; then
    emit "  OK      &${DWC3_NODE} dr_mode = \"peripheral\""
    return 0
  fi
  emit "  FAIL    &${DWC3_NODE} is not peripheral in the built DTB"
  return 1
}

verify_main() {
  ensure_build_dirs
  : >"${REPORT}"
  {
    printf '# kernel verification report\n'
    printf '# generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >>"${REPORT}"
  log_phase "Kernel verification"

  local kernel
  kernel="$(sdk_kernel_tree)" || {
    if [[ "${ALLOW_MISSING}" -eq 1 ]]; then log_warn "kernel tree not found (allowed)"; return 0; fi
    die "kernel tree not found; run 'make sdk-sync'"
  }

  if [[ ! -f "${kernel}/.config" ]]; then
    if [[ "${ALLOW_MISSING}" -eq 1 ]]; then log_warn "no .config yet (allowed)"; return 0; fi
    die "no effective .config at ${kernel#${PROJECT_ROOT}/}/.config; run 'make kernel-configure' and 'make kernel'"
  fi

  check_config "${kernel}"
  local dtb_ok=0
  check_dtb "${kernel}" && dtb_ok=1 || dtb_ok=0

  emit ""
  emit "## Summary: ${missing} missing config symbol(s); DTB check $([[ ${dtb_ok} -eq 1 ]] && echo OK || echo FAIL)"
  log_info "report: ${REPORT#${PROJECT_ROOT}/}"

  if [[ "${missing}" -gt 0 || "${dtb_ok}" -ne 1 ]]; then
    die "kernel verification FAILED"
  fi
  log_info "kernel verification: PASS"
}

verify_main
