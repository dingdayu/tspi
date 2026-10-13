#!/usr/bin/env bash
# scripts/lib/sdk.sh
# ---------------------------------------------------------------------------
# Vendor SDK location + state detection. SOURCE after common.sh:
#
#   source "${LIB_DIR}/common.sh"
#   source "${LIB_DIR}/sdk.sh"
#   load_env
#
# States (AGENTS.md section 10):
#   A = SDK absent
#   B = downloaded multi-part folder present
#   C = extracted tree with .repo/ but no synced worktree
#   D = fully synced worktree (kernel tree + device config present)
#   E = baseline build artifacts exist
#
# Detection never hard-codes the internal 20260807 layout beyond well-known
# markers; it probes for files and reports what it actually finds.
# ---------------------------------------------------------------------------

# shellcheck shell=bash

# Candidate paths (names may be overridden via config/versions.env).
sdk_vendor_candidates() {
  printf '%s\n' \
    "${SDK_VENDOR_DIR}/${SDK_VENDOR_DIRNAME:-tspi_1m_linux_kernel6.1_sdk_20260807}" \
    "${SDK_VENDOR_DIR}/tspi_1m_linux_kernel6.1_sdk_${SDK_RELEASE:-20260807}"
}

sdk_work_candidates() {
  printf '%s\n' \
    "${SDK_WORK_DIR}/${SDK_WORK_DIRNAME:-tspi-linux-sdk}"
}

# Echo the vendor intake dir if one exists, else return 1.
sdk_find_vendor_dir() {
  local d base
  while IFS= read -r d; do
    [[ -d "${d}" ]] && { printf '%s' "${d}"; return 0; }
  done < <(sdk_vendor_candidates)
  # Fallback: any dir under sdk/vendor containing the vendor extractor.
  if [[ -d "${SDK_VENDOR_DIR}" ]]; then
    for base in "${SDK_VENDOR_DIR}"/*/; do
      [[ -d "${base}" ]] || continue
      if [[ -f "${base}extract_sdk.sh" || -f "${base}build.sh" ]]; then
        printf '%s' "${base%/}"; return 0
      fi
    done
  fi
  return 1
}

# Echo the extracted/synced work tree if one exists, else return 1.
sdk_find_work_dir() {
  local d
  while IFS= read -r d; do
    [[ -d "${d}" ]] && { printf '%s' "${d}"; return 0; }
  done < <(sdk_work_candidates)
  return 1
}

# Echo the effective kernel tree path, else return 1.
sdk_kernel_tree() {
  local w; w="$(sdk_find_work_dir)" || return 1
  local k
  for k in "${w}/kernel-6.1" "${w}/kernel" "${w}"/kernel-*; do
    [[ -d "${k}" ]] && { printf '%s' "${k}"; return 0; }
  done
  return 1
}

# Print a human-readable marker report for the current SDK state.
sdk_markers() {
  local w k
  w="$(sdk_find_work_dir || true)"
  if [[ -n "${w}" ]]; then
    printf '  work tree:      %s\n' "${w}"
    [[ -d "${w}/.repo" ]]        && printf '  .repo/:         present\n' || printf '  .repo/:         absent\n'
    [[ -d "${w}/device/rockchip" ]] && printf '  device/rockchip:present\n' || printf '  device/rockchip:absent\n'
    k="$(sdk_kernel_tree || true)"
    [[ -n "${k}" ]] && printf '  kernel tree:    %s\n' "${k}" || printf '  kernel tree:    absent\n'
    [[ -d "${w}/output" ]]       && printf '  output/:        present (build artifacts)\n' || true
  fi
}

# Echo one of: A B C D E
sdk_detect_state() {
  local v w
  v="$(sdk_find_vendor_dir || true)"
  w="$(sdk_find_work_dir || true)"

  # E: baseline build artifacts exist.
  if [[ -n "${w}" && -d "${w}/output" ]] \
     && find "${w}/output" -maxdepth 3 -type f \
          \( -name '*.img' -o -name 'MiniLoaderAll.bin' -o -name 'update.img' \) \
          -print -quit 2>/dev/null | grep -q .; then
    printf 'E'; return 0
  fi

  # D: synced worktree with kernel + device config.
  if [[ -n "${w}" && -d "${w}/device/rockchip" ]] \
     && [[ -n "$(sdk_kernel_tree || true)" ]]; then
    printf 'D'; return 0
  fi

  # C: extracted tree with .repo/ (or partial work tree) but not synced.
  if [[ -n "${w}" ]]; then
    if [[ -d "${w}/.repo" || -f "${w}/build.sh" ]]; then
      printf 'C'; return 0
    fi
    # Work dir exists but is empty/unknown -> treat as C (needs sync/populate).
    printf 'C'; return 0
  fi

  # B: vendor intake folder present (extractor available), work tree absent.
  if [[ -n "${v}" ]]; then
    printf 'B'; return 0
  fi

  # A: nothing.
  printf 'A'; return 0
}

# Human label for a state code.
sdk_state_label() {
  case "$1" in
    A) printf 'A - SDK absent' ;;
    B) printf 'B - downloaded multi-part folder present' ;;
    C) printf 'C - extracted tree, worktree not synced' ;;
    D) printf 'D - fully synced worktree' ;;
    E) printf 'E - baseline build artifacts present' ;;
    *) printf 'unknown (%s)' "$1" ;;
  esac
}

# Fail with actionable placement instructions (State A).
sdk_require_present() {
  local st; st="$(sdk_detect_state)"
  if [[ "${st}" == "A" ]]; then
    local expected="${SDK_VENDOR_DIR}/${SDK_VENDOR_DIRNAME:-tspi_1m_linux_kernel6.1_sdk_20260807}"
    log_error "SDK not found."
    log_error "  Expected placement: ${expected}"
    log_error "  Then run:           make sdk-check && make sdk-extract && make sdk-sync"
    die "cannot continue without the vendor SDK"
  fi
}
