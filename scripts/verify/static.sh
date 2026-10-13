#!/usr/bin/env bash
# scripts/verify/static.sh
# Host-only static validation gate (AGENTS.md section 18.1).
#   --quick  skip optional checks (shellcheck, secrets scan)
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
load_env

QUICK=0
for arg in "$@"; do
  case "${arg}" in
    --quick) QUICK=1 ;;
    -h|--help) echo "usage: static.sh [--quick]"; exit 0 ;;
    *) die "unknown argument: ${arg}" ;;
  esac
done

failures=0
fail() { log_error "$*"; failures=$((failures + 1)); }

REQUIRED_FILES=(
  Makefile .gitignore .dockerignore README.md AGENTS.md
  builder/Dockerfile builder/entrypoint.sh builder/README.md
  config/versions.env config/build.env.example config/local.env.example
  config/packages-target.txt config/kernel-required.config
  patches/kernel/README.md
  scripts/lib/common.sh scripts/lib/sdk.sh
  scripts/host/doctor.sh scripts/host/build-builder.sh scripts/host/enter-builder.sh
  scripts/sdk/inspect.sh scripts/sdk/extract.sh scripts/sdk/sync.sh scripts/sdk/baseline-build.sh
  scripts/kernel/detect-board.sh scripts/kernel/patch.sh scripts/kernel/configure.sh
  scripts/kernel/build.sh scripts/kernel/verify.sh
  scripts/rootfs/build.sh scripts/rootfs/customize.sh scripts/rootfs/install-one-kvm.sh scripts/rootfs/verify.sh
  scripts/image/build.sh scripts/image/collect.sh scripts/image/manifest.sh
  scripts/verify/static.sh scripts/verify/target-smoke.sh
  docs/ARCHITECTURE.md docs/BUILD.md docs/HARDWARE.md docs/NETWORK.md
  docs/RECOVERY.md docs/FLASHING.md docs/VALIDATION.md docs/STATUS.md
  sdk/README.md
)

log_phase "1/5 required files"
for f in "${REQUIRED_FILES[@]}"; do
  [[ -e "${PROJECT_ROOT}/${f}" ]] || fail "missing required file: ${f}"
done
[[ "${failures}" -eq 0 ]] && log_info "all required files present"

log_phase "2/5 shell syntax (bash -n)"
syntax_fail=0
while IFS= read -r s; do
  bash -n "${s}" 2>/dev/null || { fail "syntax error: ${s#${PROJECT_ROOT}/}"; syntax_fail=$((syntax_fail + 1)); }
done < <(find "${SCRIPTS_DIR}" "${OVERLAY_DIR}/usr/local/sbin" -type f -name '*.sh' 2>/dev/null | sort)
[[ "${syntax_fail}" -eq 0 ]] && log_info "shell syntax OK"

log_phase "3/5 Makefile referenced scripts"
while IFS= read -r rel; do
  [[ -f "${PROJECT_ROOT}/${rel}" ]] || fail "Makefile references missing script: ${rel}"
done < <(grep -oE 'scripts/[a-z]+/[a-z-]+\.sh' "${PROJECT_ROOT}/Makefile" 2>/dev/null | sort -u)

log_phase "4/5 shellcheck"
if [[ "${QUICK}" -eq 1 ]]; then
  log_info "skipped (--quick)"
elif command -v shellcheck >/dev/null 2>&1; then
  if find "${SCRIPTS_DIR}" "${OVERLAY_DIR}/usr/local/sbin" -type f -name '*.sh' -print0 2>/dev/null \
       | xargs -0 shellcheck -S warning 2>/dev/null; then
    log_info "shellcheck clean"
  else
    log_warn "shellcheck reported findings (review above)"
  fi
else
  log_warn "shellcheck not installed; skipping (install it for full coverage)"
fi

log_phase "5/5 secrets hygiene"
if [[ "${QUICK}" -eq 1 ]]; then
  log_info "skipped (--quick)"
elif git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "${PROJECT_ROOT}" ls-files --error-unmatch config/local.env >/dev/null 2>&1; then
    fail "config/local.env is TRACKED by git (must be gitignored)"
  else
    log_info "config/local.env is not tracked"
  fi
  if git -C "${PROJECT_ROOT}" ls-files --error-unmatch config/build.env >/dev/null 2>&1; then
    fail "config/build.env is TRACKED by git (must be gitignored)"
  else
    log_info "config/build.env is not tracked"
  fi
  for secret_var in WIFI_PSK RECOVERY_AP_PSK; do
    local_val="${!secret_var:-}"
    [[ -z "${local_val}" ]] && continue
    if git -C "${PROJECT_ROOT}" grep -q -F -e "${local_val}" -- . >/dev/null 2>&1; then
      fail "a tracked file contains the literal value of ${secret_var} (secret leak)"
    fi
  done
  log_info "no tracked secrets detected"
else
  log_warn "not a git repository; skipping tracked-secrets scan"
fi

log_phase "Static verification summary"
if [[ "${failures}" -gt 0 ]]; then
  die "${failures} check(s) FAILED"
fi
log_info "static verification: PASS"
