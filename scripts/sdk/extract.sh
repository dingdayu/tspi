#!/usr/bin/env bash
# scripts/sdk/extract.sh
# Idempotently run the vendor SDK extractor for a downloaded multi-part SDK
# (state B). Re-running is safe; already-extracted trees are detected.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/sdk-extract.log"
WORK_LINK="${SDK_WORK_DIR}/${SDK_WORK_DIRNAME:-tspi-linux-sdk}"

# A directory is a usable SDK root when build.sh and device/rockchip exist.
is_sdk_root() {
  [[ -f "$1/build.sh" && -d "$1/device/rockchip" ]]
}

# Find a freshly extracted tree under sdk/vendor (excludes the archive folder).
find_extracted_root() {
  local d
  for d in "${SDK_VENDOR_DIR}"/*/ "${SDK_VENDOR_DIR}"/*/*/; do
    [[ -d "${d}" ]] || continue
    if is_sdk_root "${d}"; then
      printf '%s' "${d%/}"
      return 0
    fi
  done
  return 1
}

extract_main() {
  log_phase "SDK extraction"
  ensure_build_dirs
  require_cmd bash find

  local state
  state="$(sdk_detect_state)"
  log_info "state: $(sdk_state_label "${state}")"

  case "${state}" in
    A) sdk_require_present ;;
    C|D|E) log_info "work tree already exists; nothing to extract"; return 0 ;;
  esac

  local vendor
  vendor="$(sdk_find_vendor_dir)" || die "cannot locate the vendor intake folder under ${SDK_VENDOR_DIR}"
  log_info "vendor folder: ${vendor#${PROJECT_ROOT}/}"

  if find_extracted_root >/dev/null; then
    log_info "an extracted SDK root already exists; skipping extraction"
  else
    local extractor="${vendor}/extract_sdk.sh"
    if [[ -f "${extractor}" ]]; then
      log_phase "Running vendor extractor (this can take a while)"
      ( cd "${vendor}" && run_logged "${LOG_FILE}" bash "${extractor}" )
    elif compgen -G "${vendor}/*.tar*" >/dev/null || compgen -G "${vendor}/*.tgz" >/dev/null; then
      die "no extract_sdk.sh found but archives are present in ${vendor}. Extract them manually, then re-run 'make sdk-extract'."
    else
      die "no extract_sdk.sh and no archives found in ${vendor}. Verify the SDK download."
    fi
  fi

  local root
  if root="$(find_extracted_root)"; then
    mkdir -p "${SDK_WORK_DIR}"
    if [[ ! -e "${WORK_LINK}" ]]; then
      ln -sfn "${root}" "${WORK_LINK}"
      log_info "linked ${WORK_LINK#${PROJECT_ROOT}/} -> ${root#${PROJECT_ROOT}/}"
    fi
  else
    die "extraction finished but no SDK root (build.sh + device/rockchip) was found under ${SDK_VENDOR_DIR}."
  fi

  log_info "extraction complete. Next: make sdk-sync"
}

extract_main
