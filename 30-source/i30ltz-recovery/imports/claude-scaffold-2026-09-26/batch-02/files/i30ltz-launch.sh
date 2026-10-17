#!/usr/bin/env bash
# i30LTZ Recovery OS — Entry Point Launcher
# v0.1.0 | 2026-09-26

set -euo pipefail

PREFIX="/opt/i30ltz"
LOG_DIR="/var/log/i30ltz"
DATA_DIR="/var/lib/i30ltz"

mkdir -p "$LOG_DIR"
mkdir -p "$DATA_DIR/cases"

export I30LTZ_LOG="${I30LTZ_LOG:-info}"
export I30LTZ_CONFIG="${I30LTZ_CONFIG:-$PREFIX/config/i30ltz.toml}"

echo "[i30LTZ] v0.1.0 | 2026-09-26 — launching shell..."
exec "$PREFIX/bin/i30ltz-shell" "$@" 2>>"$LOG_DIR/shell.log"
