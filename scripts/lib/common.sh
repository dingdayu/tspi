#!/usr/bin/env bash
# scripts/lib/common.sh
# ---------------------------------------------------------------------------
# Shared helpers for every project script. SOURCE this file; do not execute it.
#
#   source "$(dirname "$0")/../lib/common.sh"   # from scripts/<group>/
#
# Provides: strict mode, project path variables, logging, assertion helpers,
# environment loading, and log redaction. See scripts/lib/sdk.sh for SDK state.
# ---------------------------------------------------------------------------

set -Eeuo pipefail

# --- Project root (robust to being sourced from anywhere) ------------------
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  _common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "${_common_dir}/../.." && pwd)"
  unset _common_dir
fi
export PROJECT_ROOT

# --- Canonical paths -------------------------------------------------------
CONFIG_DIR="${PROJECT_ROOT}/config"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
LIB_DIR="${SCRIPTS_DIR}/lib"
BUILDER_DIR="${PROJECT_ROOT}/builder"
PATCHES_DIR="${PROJECT_ROOT}/patches"
OVERLAY_DIR="${PROJECT_ROOT}/rootfs-overlay"
DOCS_DIR="${PROJECT_ROOT}/docs"
SDK_DIR="${PROJECT_ROOT}/sdk"
SDK_VENDOR_DIR="${PROJECT_ROOT}/sdk/vendor"
SDK_WORK_DIR="${PROJECT_ROOT}/sdk/work"
DOWNLOADS_DIR="${PROJECT_ROOT}/downloads"
BUILD_DIR="${PROJECT_ROOT}/build"
LOGS_DIR="${BUILD_DIR}/logs"
DIST_DIR="${PROJECT_ROOT}/dist"
export CONFIG_DIR SCRIPTS_DIR LIB_DIR BUILDER_DIR PATCHES_DIR OVERLAY_DIR \
  DOCS_DIR SDK_DIR SDK_VENDOR_DIR SDK_WORK_DIR DOWNLOADS_DIR BUILD_DIR \
  LOGS_DIR DIST_DIR

# --- Terminal-aware logging ------------------------------------------------
if [[ -t 2 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  _C_RESET="$(tput sgr0)"; _C_BOLD="$(tput bold)"
  _C_BLUE="$(tput setaf 4)"; _C_GREEN="$(tput setaf 2)"
  _C_YELLOW="$(tput setaf 3)"; _C_RED="$(tput setaf 1)"
else
  _C_RESET=""; _C_BOLD=""; _C_BLUE=""; _C_GREEN=""; _C_YELLOW=""; _C_RED=""
fi

log_phase() { printf '\n%s==> %s%s\n' "${_C_BOLD}${_C_BLUE}" "$*" "${_C_RESET}" >&2; }
log_info()  { printf '%s[kvm]%s %s\n' "${_C_GREEN}" "${_C_RESET}" "$*" >&2; }
log_warn()  { printf '%s[warn]%s %s\n' "${_C_YELLOW}" "${_C_RESET}" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n' "${_C_RED}" "${_C_RESET}" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

# --- Assertions ------------------------------------------------------------
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: '$c' (install it or use the builder container)"
  done
}

require_file() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] || die "missing required file: $f"
  done
}

require_dir() {
  local d
  for d in "$@"; do
    [[ -d "$d" ]] || die "missing required directory: $d"
  done
}

# --- Redaction (never leak secrets to logs) --------------------------------
# Usage: redact_secret "$WIFI_PSK"  -> prints "***" (or "" if empty)
redact_secret() { [[ -n "${1:-}" ]] && printf '***' || printf ''; }

# Filter a stream, masking KEY=VALUE secrets. Usage: cmd 2>&1 | sanitize_stream
sanitize_stream() {
  sed -E 's/((PSK|PASSWORD|PASSWD|SECRET|TOKEN|KEY)[A-Za-z_]*=)[^[:space:]]+/\1***/gI'
}

# --- Environment loading ---------------------------------------------------
# Order (later wins): versions.env -> build.env -> local.env
# config/local.env and config/build.env are gitignored; absence is normal.
load_env() {
  local f
  for f in versions.env build.env local.env; do
    if [[ -f "${CONFIG_DIR}/${f}" ]]; then
      set -a
      # shellcheck disable=SC1090
      . "${CONFIG_DIR}/${f}"
      set +a
    fi
  done
}

# --- Container engine ------------------------------------------------------
# Echo "docker" or "podman" (first available), else return 1.
detect_container_engine() {
  if command -v docker >/dev/null 2>&1; then printf 'docker'
  elif command -v podman >/dev/null 2>&1; then printf 'podman'
  else return 1; fi
}

require_container_engine() {
  local e
  e="$(detect_container_engine)" || die "neither docker nor podman is available (the builder container requires one)"
  printf '%s' "${e}"
}

# --- Build dir helpers -----------------------------------------------------
ensure_build_dirs() { mkdir -p "${BUILD_DIR}" "${LOGS_DIR}" "${DIST_DIR}"; }

# Run a command, teeing combined output to a log file.
# Usage: run_logged <logfile> <cmd> [args...]
run_logged() {
  local log="$1"; shift
  mkdir -p "$(dirname "${log}")"
  log_info "logging to ${log#${PROJECT_ROOT}/}"
  { "$@"; } 2>&1 | sanitize_stream | tee -a "${log}"
  return "${PIPESTATUS[0]}"
}

# --- Misc ------------------------------------------------------------------
# First existing path from the arguments, else empty.
first_existing() {
  local p
  for p in "$@"; do
    [[ -e "${p}" ]] && { printf '%s' "${p}"; return 0; }
  done
  return 1
}

# Join an array of non-empty tokens with a separator.
join_by() { local IFS="$1"; shift; printf '%s' "$*"; }
