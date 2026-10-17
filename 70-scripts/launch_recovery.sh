#!/usr/bin/env bash
# Launch Dr. I30LTZ Recovery GUI (Raylib Kiosk) on Debian or Recovery OS
set -euo pipefail

# Environment / auth configuration
[ -f /etc/i30ltz/boltz.env ] && . /etc/i30ltz/boltz.env || true
[ -n "${BOLTZ_AUTH_TOKEN:-}" ] && export SWARM_AUTH_TOKEN="$BOLTZ_AUTH_TOKEN" || true
export LUCY_URL="${LUCY_URL:-http://127.0.0.1:7300}"

BIN_CANDIDATES=(
  "/mnt/recoverybuild/30-source/i30ltz-recovery/target/release/i30ltz-recovery"
  "/usr/local/bin/i30ltz-recovery"
  "/opt/i30ltz/bin/i30ltz-recovery"
)

BIN=""
for b in "${BIN_CANDIDATES[@]}"; do
  if [[ -x "$b" ]]; then
    BIN="$b"
    break
  fi
done

if [[ -z "$BIN" ]]; then
  echo "Error: i30ltz-recovery binary not found." >&2
  exit 1
fi

cd "$(dirname "$BIN")"
exec "$BIN" "$@"
