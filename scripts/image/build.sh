#!/usr/bin/env bash
# scripts/image/build.sh
# ---------------------------------------------------------------------------
# Package the vendor SDK images and collect flashing artifacts into dist/.
#
# Invoked by `make image` inside the builder container:
#   scripts/host/enter-builder.sh -- scripts/image/build.sh
#
# Flow:
#   1. require a synced SDK with a completed baseline build (state E);
#   2. probe the vendor build.sh for available packaging subcommands;
#   3. run the configured/auto-detected packaging subcommand(s);
#   4. delegate artifact collection to scripts/image/collect.sh.
#
# The vendor build.sh subcommand names are DETECTED, never assumed. Override
# the packaging subcommand(s) explicitly with IMAGE_BUILD_CMD, e.g.
#   IMAGE_BUILD_CMD="firmware updateimg" make image
#
# No hardware flashing and no raw block-device writes happen here.
# ---------------------------------------------------------------------------
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/image-build.log"

# Known Rockchip SDK build.sh subcommands. Used only for probing/reporting;
# the script never assumes any of them exist.
KNOWN_SUBCOMMANDS=(lunch uboot kernel rootfs firmware updateimg all clean help save)

# --- Vendor build.sh probing ----------------------------------------------
# Run the vendor usage/help handler, but only if the script actually has one.
# This avoids accidentally triggering a build when `help` is unrecognized.
probe_help() {
  local build_sh="$1" out=""
  if ! grep -qE '(^|[^[:alnum:]_])(usage|help)([^[:alnum:]_]|$)' "${build_sh}" 2>/dev/null; then
    printf ''
    return 0
  fi
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout 30 bash "${build_sh}" help 2>&1)" || true
    if [[ -z "${out}" ]]; then
      out="$(timeout 30 bash "${build_sh}" --help 2>&1)" || true
    fi
  else
    out="$(bash "${build_sh}" help 2>&1)" || true
    if [[ -z "${out}" ]]; then
      out="$(bash "${build_sh}" --help 2>&1)" || true
    fi
  fi
  printf '%s' "${out}"
}

# Return 0 if a subcommand is advertised by help output or present in source.
subcommand_available() {
  local name="$1" help_text="$2" build_sh="$3"
  if [[ -n "${help_text}" ]] \
     && grep -qE "(^|[^[:alnum:]_-])${name}([^[:alnum:]_-]|$)" <<<"${help_text}"; then
    return 0
  fi
  grep -qE "(^|[^[:alnum:]_-])${name}([^[:alnum:]_-]|$)" "${build_sh}" 2>/dev/null
}

# Run the vendor build.sh from the SDK work tree root.
run_vendor() {
  local work="$1" build_sh="$2"
  shift 2
  cd "${work}"
  bash "${build_sh}" "$@"
}

# --- Main ------------------------------------------------------------------
build_main() {
  log_phase "Image packaging (vendor SDK)"
  ensure_build_dirs
  require_cmd bash find grep cp
  sdk_require_present

  local state
  state="$(sdk_detect_state)"
  log_info "SDK state: $(sdk_state_label "${state}")"
  case "${state}" in
    A) sdk_require_present ;;
    B) die "SDK is downloaded but not extracted. Run: make sdk-extract && make sdk-sync" ;;
    C) die "SDK work tree is not synced. Run: make sdk-sync" ;;
    D) die "No baseline build artifacts found (state D). Run 'make baseline' (then 'make kernel rootfs') before packaging." ;;
    E) : ;;
    *) die "unexpected SDK state '${state}'" ;;
  esac

  local work
  work="$(sdk_find_work_dir)" || die "cannot locate the SDK work tree under ${SDK_WORK_DIR}"
  local build_sh="${work}/build.sh"
  require_file "${build_sh}"
  log_info "vendor build script: ${build_sh#${PROJECT_ROOT}/}"

  # Probe available subcommands (non-fatal; detection only).
  local help_text
  help_text="$(probe_help "${build_sh}")"
  local available=() c
  for c in "${KNOWN_SUBCOMMANDS[@]}"; do
    if subcommand_available "${c}" "${help_text}" "${build_sh}"; then
      available+=("${c}")
    fi
  done
  if [[ ${#available[@]} -gt 0 ]]; then
    log_info "detected build.sh subcommands: ${available[*]}"
  else
    log_warn "could not detect any known build.sh subcommands; will rely on IMAGE_BUILD_CMD"
  fi

  # Determine which packaging subcommand(s) to run.
  local -a cmds=()
  if [[ -n "${IMAGE_BUILD_CMD:-}" ]]; then
    read -r -a cmds <<<"${IMAGE_BUILD_CMD}"
    log_info "using IMAGE_BUILD_CMD override: ${cmds[*]}"
  else
    for c in firmware updateimg; do
      subcommand_available "${c}" "${help_text}" "${build_sh}" && cmds+=("${c}")
    done
    if [[ ${#cmds[@]} -eq 0 ]] \
       && subcommand_available "all" "${help_text}" "${build_sh}"; then
      cmds=(all)
    fi
  fi
  if [[ ${#cmds[@]} -eq 0 ]]; then
    die "could not determine a packaging subcommand. Detected: ${available[*]:-none}. Set IMAGE_BUILD_CMD explicitly (e.g. IMAGE_BUILD_CMD=firmware)."
  fi

  : >"${LOG_FILE}"
  for c in "${cmds[@]}"; do
    log_phase "Running vendor build.sh ${c}"
    run_logged "${LOG_FILE}" run_vendor "${work}" "${build_sh}" "${c}"
  done

  log_phase "Collecting artifacts into dist/"
  bash "${SCRIPTS_DIR}/image/collect.sh"

  log_info "image packaging complete; see ${LOG_FILE#${PROJECT_ROOT}/}"
}

run_logged "${LOG_FILE}" build_main
