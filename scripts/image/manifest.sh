#!/usr/bin/env bash
# scripts/image/manifest.sh
# Generate dist/MANIFEST.txt and dist/SHA256SUMS from the collected artifacts
# and the build's known versions/revisions. Runs on the host.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/lib/sdk.sh"
load_env

MANIFEST="${DIST_DIR}/MANIFEST.txt"
SUMS="${DIST_DIR}/SHA256SUMS"

kernel_field() {
  local k="$1" rev="unknown" ver="unknown"
  if [[ -n "${k}" ]]; then
    ver="$(sed -n 's/^VERSION = //p' "${k}/Makefile" 2>/dev/null | head -1).$(sed -n 's/^PATCHLEVEL = //p' "${k}/Makefile" 2>/dev/null | head -1)"
    rev="$(git -C "${k}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    [[ "${ver}" == "." ]] && ver="unknown"
  fi
  printf '%s commit=%s' "${ver}" "${rev}"
}

manifest_main() {
  log_phase "Generating dist manifest + checksums"
  ensure_build_dirs
  require_cmd sha256sum

  local -a arts=()
  while IFS= read -r f; do arts+=("$(basename "${f}")"); done \
    < <(find "${DIST_DIR}" -maxdepth 1 -type f \
          \( -name '*.img' -o -name '*.bin' -o -name '*.dtb' -o -name 'parameter.txt' -o -name '*.upd' \) | sort)
  if [[ ${#arts[@]} -eq 0 ]]; then
    die "no artifacts in ${DIST_DIR#${PROJECT_ROOT}/}; run 'make image' first"
  fi

  local work kernel sdk_rev
  work="$(sdk_find_work_dir 2>/dev/null || true)"
  kernel="$(sdk_kernel_tree 2>/dev/null || true)"
  sdk_rev="unknown"
  [[ -n "${work}" && -d "${work}/.repo/manifests" ]] && sdk_rev="$(git -C "${work}/.repo/manifests" rev-parse --short HEAD 2>/dev/null || echo unknown)"

  local pkg_hash="unknown"
  [[ -f "${CONFIG_DIR}/packages-target.txt" ]] && pkg_hash="$(sha256sum "${CONFIG_DIR}/packages-target.txt" | awk '{print $1}')"
  local board="unknown"
  [[ -n "${work}" ]] && board="$(basename "$(readlink -f "${work}/output/defconfig" 2>/dev/null)" 2>/dev/null || echo unknown)"

  {
    printf 'MANIFEST\n'
    printf '========\n'
    printf 'build_timestamp_utc: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'sdk_name:            %s\n' "${SDK_NAME:-unknown}"
    printf 'sdk_release:         %s\n' "${SDK_RELEASE:-unknown}"
    printf 'sdk_manifest_rev:    %s\n' "${sdk_rev}"
    printf 'kernel:              %s\n' "$(kernel_field "${kernel}")"
    printf 'board_defconfig:     %s\n' "${board}"
    printf 'one_kvm_version:     %s (%s)\n' "${ONE_KVM_VERSION:-unknown}" "${ONE_KVM_TAG:-unknown}"
    printf 'packages_target_sha: %s\n' "${pkg_hash}"
    printf '\nartifacts:\n'
    ( cd "${DIST_DIR}" && sha256sum "${arts[@]}" )
  } >"${MANIFEST}"

  ( cd "${DIST_DIR}" && sha256sum "${arts[@]}" >"${SUMS}" )
  local msum
  msum="$(sha256sum "${MANIFEST}" | awk '{print $1}')"
  printf 'manifest_sha256:     %s\n' "${msum}" >>"${MANIFEST}"

  log_info "manifest: ${MANIFEST#${PROJECT_ROOT}/}"
  log_info "checksums: ${SUMS#${PROJECT_ROOT}/} (${#arts[@]} artifact(s))"
}

manifest_main
