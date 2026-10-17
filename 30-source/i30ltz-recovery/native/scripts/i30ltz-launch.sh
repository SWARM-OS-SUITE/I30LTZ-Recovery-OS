#!/usr/bin/env bash
set -euo pipefail
PREFIX="${I30LTZ_PREFIX:-/opt/i30ltz}"
if [[ ! -x "$PREFIX/bin/i30ltz-shell" ]]; then
  echo "Missing $PREFIX/bin/i30ltz-shell; build/install the native workspace first." >&2
  exit 1
fi
if [[ -n "${I30LTZ_PREFIX+x}" && -z "${I30LTZ_CONFIG+x}" && -f "$PREFIX/config/i30ltz.toml" ]]; then
  export I30LTZ_CONFIG="$PREFIX/config/i30ltz.toml"
fi
exec "$PREFIX/bin/i30ltz-shell" "$@"
