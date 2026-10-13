#!/usr/bin/env bash
# scripts/host/doctor.sh
# Validate the development host, configuration, and SDK presence.
#   --print-sdk-state  print only A..E (used by `make all`) and exit 0
#   --strict           treat missing secrets/key as fatal (production)
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

PRINT_STATE=0
STRICT=0
for arg in "$@"; do
  case "${arg}" in
    --print-sdk-state) PRINT_STATE=1 ;;
    --strict) STRICT=1 ;;
    -h|--help) echo "usage: doctor.sh [--print-sdk-state] [--strict]"; exit 0 ;;
    *) die "unknown argument: ${arg}" ;;
  esac
done

if [[ "${PRINT_STATE}" -eq 1 ]]; then
  sdk_detect_state
  exit 0
fi

failures=0
warnings=0
fail() { log_error "$*"; failures=$((failures + 1)); }
warn() { log_warn "$*"; warnings=$((warnings + 1)); }

log_phase "Host doctor"

if engine="$(detect_container_engine)"; then
  log_info "container engine: ${engine}"
else
  fail "neither docker nor podman found (the builder container requires one)"
fi

for c in git make; do
  command -v "${c}" >/dev/null 2>&1 || fail "missing required command: ${c}"
done
command -v shellcheck >/dev/null 2>&1 || warn "shellcheck not installed (optional; 'make verify' will skip it)"

for f in builder/Dockerfile builder/entrypoint.sh config/versions.env \
         config/build.env.example config/local.env.example \
         config/packages-target.txt config/kernel-required.config; do
  [[ -f "${PROJECT_ROOT}/${f}" ]] || fail "missing required file: ${f}"
done

log_phase "Configuration"
if [[ -f "${CONFIG_DIR}/local.env" ]]; then
  log_info "config/local.env present (secrets loaded; never printed)"
elif [[ "${STRICT}" -eq 1 ]]; then
  fail "config/local.env missing (copy config/local.env.example and fill it in)"
else
  warn "config/local.env missing; Wi-Fi/SSH provisioning will be incomplete"
fi

if [[ "${ALLOW_PASSWORD_SSH:-0}" != "1" && -z "${SSH_PUBLIC_KEY_FILE:-}" ]]; then
  msg="no SSH public key configured and ALLOW_PASSWORD_SSH=0; the image would be unreachable over SSH (AGENTS.md section 2.6)"
  if [[ "${STRICT}" -eq 1 ]]; then fail "${msg}"; else warn "${msg}"; fi
fi
if [[ -n "${SSH_PUBLIC_KEY_FILE:-}" && ! -f "${SSH_PUBLIC_KEY_FILE}" ]]; then
  fail "SSH_PUBLIC_KEY_FILE points to a missing file: ${SSH_PUBLIC_KEY_FILE}"
fi

log_phase "SDK"
state="$(sdk_detect_state)"
log_info "state: $(sdk_state_label "${state}")"
sdk_markers
if [[ "${state}" == "A" ]]; then
  log_info "place the SDK at ${SDK_VENDOR_DIR}/${SDK_VENDOR_DIRNAME:-tspi_1m_linux_kernel6.1_sdk_20260807}"
  log_info "then run: make sdk-check && make sdk-extract && make sdk-sync"
fi

log_phase "Summary"
log_info "failures: ${failures}, warnings: ${warnings}"
if [[ "${failures}" -gt 0 ]]; then
  die "${failures} hard failure(s); fix the above before building"
fi
log_info "doctor: OK"
