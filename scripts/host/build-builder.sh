#!/usr/bin/env bash
# scripts/host/build-builder.sh
# Build the Ubuntu 22.04 builder container image.
#   FORCE=1  rebuild without cache
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
load_env

ensure_build_dirs
engine="$(require_container_engine)"
require_cmd bash
require_file "${BUILDER_DIR}/Dockerfile" "${BUILDER_DIR}/entrypoint.sh"

image_ref="${BUILDER_IMAGE_REF:-taishanpi-kvm-builder:22.04}"
log_phase "Building builder image ${image_ref} (${engine})"

args=(build --tag "${image_ref}" --file "${BUILDER_DIR}/Dockerfile")
if [[ "${FORCE:-0}" == "1" ]]; then
  args+=(--no-cache)
  log_info "FORCE=1: rebuilding without cache"
fi
args+=("${BUILDER_DIR}")

run_logged "${LOGS_DIR}/build-builder.log" "${engine}" "${args[@]}"
log_info "builder image ready: ${image_ref}"
