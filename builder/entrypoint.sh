#!/usr/bin/env bash
# builder/entrypoint.sh — container entrypoint for the build sandbox.
set -Eeuo pipefail

# Bind-mounted repository root.
WORKDIR="${WORKDIR:-/work}"

if [[ ! -d "${WORKDIR}" ]]; then
  echo "[error] bind mount missing: ${WORKDIR}" >&2
  exit 1
fi

# Make repo scripts executable if the host mount lost the bit.
if [[ -d "${WORKDIR}/scripts" ]]; then
  find "${WORKDIR}/scripts" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
fi

# Ensure common mount points for vendor chroot/binfmt workflows.
mkdir -p /proc/sys/fs/binfmt_misc 2>/dev/null || true

echo "[builder] TaishanPi RK3566 SDK sandbox"
echo "[builder]   python   -> $(python --version 2>&1)"
echo "[builder]   python2  -> $(python2.7 --version 2>&1 || echo 'not installed')"
echo "[builder]   workdir  -> ${WORKDIR}"
echo "[builder]   repo     -> ${WORKDIR} (bind-mounted)"

# If a command was supplied, run it; otherwise drop into a shell.
if [[ "$#" -gt 0 ]]; then
  exec "$@"
fi
exec /bin/bash
