#!/usr/bin/env bash
# Launch I30LTZ IDE (Flutter + local MAD AI) on Debian or Recovery OS
set -euo pipefail

BUNDLE_CANDIDATES=(
  "/mnt/recoverybuild/30-source/i30ltz-ide/build/linux/x64/release/bundle"
  "/opt/i30ltz/ide"
)

APP_DIR=""
for dir in "${BUNDLE_CANDIDATES[@]}"; do
  if [[ -x "$dir/i30ltz_ide" ]]; then
    APP_DIR="$dir"
    break
  fi
done

if [[ -z "$APP_DIR" ]]; then
  echo "Error: i30ltz_ide binary not found." >&2
  exit 1
fi

cd "$APP_DIR"
exec ./i30ltz_ide "$@"
