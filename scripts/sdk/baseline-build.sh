#!/usr/bin/env bash
# scripts/sdk/baseline-build.sh
# Smallest practical UNMODIFIED vendor build, to prove the toolchain and SDK
# are healthy before our One-KVM patches. The vendor build.sh flow is detected,
# never assumed; override with BASELINE_BUILD_CMD.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/baseline-build.log"
CHIP="${SDK_CHIP_DIRNAME:-rk3566_rk3568}"
DEFCONFIG_GLOB="${SDK_BOARD_DEFCONFIG_GLOB:-*taishanpi*_defconfig}"

detect_board_defconfig() {
  local w="$1"
  local dir="${w}/device/rockchip/.chips/${CHIP}"
  local hit
  hit="$(find "${dir}" -maxdepth 1 -name "${DEFCONFIG_GLOB}" -print -quit 2>/dev/null || true)"
  if [[ -z "${hit}" ]]; then
    hit="$(find "${w}/device/rockchip" -maxdepth 3 -name "${DEFCONFIG_GLOB}" -print -quit 2>/dev/null || true)"
  fi
  [[ -n "${hit}" ]] && printf '%s' "$(basename "${hit}")"
}

baseline_main() {
  log_phase "Vendor baseline build (unmodified SDK)"
  ensure_build_dirs
  require_cmd bash

  local state
  state="$(sdk_detect_state)"
  case "${state}" in
    A) sdk_require_present ;;
    B) die "SDK not extracted. Run: make sdk-extract && make sdk-sync" ;;
    C) die "SDK not synced. Run: make sdk-sync" ;;
    E) log_info "baseline artifacts already present (state E); re-running anyway" ;;
  esac

  local work
  work="$(sdk_find_work_dir)" || die "cannot locate the SDK work tree under ${SDK_WORK_DIR}"
  local build_sh="${work}/build.sh"
  require_file "${build_sh}"

  : >"${LOG_FILE}"

  if [[ -n "${BASELINE_BUILD_CMD:-}" ]]; then
    log_info "using BASELINE_BUILD_CMD override: ${BASELINE_BUILD_CMD}"
    ( cd "${work}" && run_logged "${LOG_FILE}" bash -c "${BASELINE_BUILD_CMD}" )
  else
    local defconfig
    defconfig="$(detect_board_defconfig "${work}")"
    if [[ -z "${defconfig}" ]]; then
      die "could not detect a board defconfig matching '${DEFCONFIG_GLOB}'. Set BASELINE_BUILD_CMD explicitly, e.g. BASELINE_BUILD_CMD='./build.sh lunch:rockchip_rk3566_taishanpi_1m_v10_defconfig && ./build.sh'."
    fi
    log_info "detected board defconfig: ${defconfig}"
    log_phase "Selecting config and building (this is a long vendor build)"
    ( cd "${work}" && run_logged "${LOG_FILE}" bash "${build_sh}" "${defconfig}" )
    ( cd "${work}" && run_logged "${LOG_FILE}" bash "${build_sh}" )
  fi

  state="$(sdk_detect_state)"
  log_info "post-build state: $(sdk_state_label "${state}")"
  log_info "baseline build finished; log: ${LOG_FILE#${PROJECT_ROOT}/}"
}

baseline_main
