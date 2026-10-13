#!/usr/bin/env bash
# scripts/sdk/sync.sh
# Idempotently populate the extracted work tree using the LOCAL repo tool
# (no network). Safe to re-run on an already-synced tree.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

LOG_FILE="${LOGS_DIR}/sdk-sync.log"

find_repo_tool() {
  local w="$1"
  if [[ -x "${w}/.repo/repo/repo" ]]; then
    printf '%s' "${w}/.repo/repo/repo"
  elif command -v repo >/dev/null 2>&1; then
    command -v repo
  else
    return 1
  fi
}

sync_main() {
  log_phase "SDK local sync"
  ensure_build_dirs
  require_cmd bash git

  local state
  state="$(sdk_detect_state)"
  log_info "state: $(sdk_state_label "${state}")"

  case "${state}" in
    A) sdk_require_present ;;
    B) die "SDK not extracted yet. Run: make sdk-extract" ;;
    D|E) log_info "work tree already synced (state ${state}); nothing to do"; return 0 ;;
  esac

  local work
  work="$(sdk_find_work_dir)" || die "cannot locate the work tree under ${SDK_WORK_DIR}"
  require_dir "${work}/.repo"

  local repo_tool
  repo_tool="$(find_repo_tool "${work}")" || die "repo tool not found (looked for .repo/repo/repo and 'repo' on PATH)"
  log_info "repo tool: ${repo_tool#${PROJECT_ROOT}/}"

  local jobs
  jobs="$(nproc 2>/dev/null || echo 4)"
  log_phase "repo sync -l -j${jobs} (local, no network)"
  ( cd "${work}" && run_logged "${LOG_FILE}" "${repo_tool}" sync -l -j"${jobs}" )

  state="$(sdk_detect_state)"
  log_info "post-sync state: $(sdk_state_label "${state}")"
  [[ "${state}" == "D" || "${state}" == "E" ]] || die "sync finished but the tree still does not look synced; see ${LOG_FILE#${PROJECT_ROOT}/}"
  log_info "sync complete. Next: make baseline"
}

sync_main
