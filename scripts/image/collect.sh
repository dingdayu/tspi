#!/usr/bin/env bash
# scripts/image/collect.sh
# ---------------------------------------------------------------------------
# Discover the vendor SDK output layout and copy the real flashing artifacts
# into dist/. Called by scripts/image/build.sh (and by manifest.sh when dist/
# is empty).
#
# Only artifacts that actually exist are copied; the report records which were
# found vs absent. Re-running is safe (files are overwritten in place).
#
# No hardware flashing and no raw block-device writes happen here.
# ---------------------------------------------------------------------------
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/image-collect.log"
REPORT_FILE="${BUILD_DIR}/image-collect.txt"

# Canonical flashing artifacts (AGENTS.md section 17). Not all are expected.
ARTIFACTS=(boot.img rootfs.img uboot.img MiniLoaderAll.bin parameter.txt update.img)

# Candidate vendor output directories, in priority order.
collect_search_dirs() {
  local w="$1" d
  for d in \
    "${w}/rockdev" \
    "${w}/output/firmware" \
    "${w}/output/rockdev" \
    "${w}/output/update/Image" \
    "${w}/output/update" \
    "${w}/output"; do
    [[ -d "${d}" ]] && printf '%s\n' "${d}"
  done
  for d in "${w}"/output/rockchip_*; do
    [[ -d "${d}" ]] && printf '%s\n' "${d}"
  done
}

# Echo the first matching artifact path across the search dirs, else return 1.
find_artifact() {
  local name="$1"
  shift
  local dir hit
  for dir in "$@"; do
    hit="$(find "${dir}" -maxdepth 2 -name "${name}" \( -type f -o -type l \) -print -quit 2>/dev/null || true)"
    if [[ -n "${hit}" ]]; then
      printf '%s' "${hit}"
      return 0
    fi
  done
  return 1
}

# Device-tree blobs present in the vendor output dirs.
find_output_dtbs() {
  local dir
  for dir in "$@"; do
    find "${dir}" -maxdepth 2 -name '*.dtb' -type f -print 2>/dev/null || true
  done | sort -u
}

# Board-specific DTBs from the kernel tree (fallback when output has none).
find_board_dtbs() {
  local w="$1" k d
  k="$(sdk_kernel_tree || true)"
  [[ -n "${k}" ]] || return 0
  d="${k}/arch/arm64/boot/dts/rockchip"
  [[ -d "${d}" ]] || return 0
  find "${d}" -maxdepth 1 -name "*${TARGET_BOARD}*.dtb" -type f -print 2>/dev/null || true
}

collect_main() {
  log_phase "Collecting vendor image artifacts into dist/"
  ensure_build_dirs
  require_cmd find cp sha256sum
  sdk_require_present

  local state
  state="$(sdk_detect_state)"
  case "${state}" in
    A) sdk_require_present ;;
    B|C) die "SDK not synced (state ${state}). Run: make sdk-extract && make sdk-sync" ;;
  esac

  local work
  work="$(sdk_find_work_dir)" || die "cannot locate the SDK work tree under ${SDK_WORK_DIR}"

  local -a dirs=()
  mapfile -t dirs < <(collect_search_dirs "${work}")
  if [[ ${#dirs[@]} -eq 0 ]]; then
    die "no vendor output directories found under ${work#${PROJECT_ROOT}/} (looked for rockdev/, output/, output/firmware, output/rockchip_*). Run 'make image' first."
  fi
  log_info "searching: ${dirs[*]}"

  {
    printf '# image collect report\n'
    printf '# generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# work tree: %s\n' "${work}"
  } >"${REPORT_FILE}"

  local found=0 name src
  for name in "${ARTIFACTS[@]}"; do
    if src="$(find_artifact "${name}" "${dirs[@]}")"; then
      cp -f "${src}" "${DIST_DIR}/${name}"
      log_info "collected ${name}  <- ${src#${PROJECT_ROOT}/}"
      printf 'present %s %s\n' "${name}" "${src}" >>"${REPORT_FILE}"
      found=$((found + 1))
    else
      log_warn "absent  ${name}"
      printf 'absent %s\n' "${name}" >>"${REPORT_FILE}"
    fi
  done

  # Device trees: prefer vendor output, fall back to the board DTBs.
  local -a dtbs=()
  mapfile -t dtbs < <(find_output_dtbs "${dirs[@]}")
  if [[ ${#dtbs[@]} -eq 0 ]]; then
    mapfile -t dtbs < <(find_board_dtbs "${work}")
  fi
  for src in "${dtbs[@]}"; do
    cp -f "${src}" "${DIST_DIR}/$(basename "${src}")"
    log_info "collected $(basename "${src}")  <- ${src#${PROJECT_ROOT}/}"
    printf 'present %s %s\n' "$(basename "${src}")" "${src}" >>"${REPORT_FILE}"
  done

  if [[ ${found} -eq 0 && ${#dtbs[@]} -eq 0 ]]; then
    die "no artifacts found in the vendor output; packaging may have failed. See ${LOG_FILE#${PROJECT_ROOT}/}"
  fi

  log_info "collected ${found} image artifact(s) and ${#dtbs[@]} dtb(s) into dist/"
  log_info "report: ${REPORT_FILE#${PROJECT_ROOT}/}"
}

run_logged "${LOG_FILE}" collect_main
