#!/usr/bin/env bash
# Installs system build tools only. Install a current Rust toolchain as your user.
set -euo pipefail
source /etc/os-release
if [[ "${ID:-}" != debian || "${VERSION_ID:-}" != 12 ]]; then
  echo 'This installer targets Debian 12 only.' >&2
  exit 1
fi
if (( EUID != 0 )); then
  echo 'Run this system dependency installer with sudo.' >&2
  exit 1
fi
apt-get update
apt-get install -y --no-install-recommends build-essential pkg-config ca-certificates
printf '%s
' 'System tools installed. Use a current Rust toolchain as your normal user.' \
  'The scaffold uses bundled SQLite. Slint and llama.cpp integration are later milestones.'
