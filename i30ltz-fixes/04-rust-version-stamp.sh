#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# FIX Medium-4 — Add version + date stamp to Raylib GUI title bar
# I30LTZ Recovery OS · 2026-10-06
# Run on: i30ltz-x13-gen-1 as normal user
# ─────────────────────────────────────────────────────────────
set -euo pipefail

RUST_SRC_GLOB="/mnt/recoverybuild/30-source/mad-dr-boltz/src/main.rs"
VERSION="v0.2.0-alpha"
BUILD_DATE="2026-10-06"
FIX_TAG="// [FIX-2026-10-06] version stamp"

echo "==> [Medium-4] Patching Rust source for version stamp in window title..."

# Find main.rs - try the expected path first, then search
if [[ -f "$RUST_SRC_GLOB" ]]; then
  MAIN_RS="$RUST_SRC_GLOB"
else
  MAIN_RS=$(find /mnt/recoverybuild/30-source -name "main.rs" 2>/dev/null | head -1)
fi

if [[ -z "$MAIN_RS" || ! -f "$MAIN_RS" ]]; then
  echo "ERROR: main.rs not found in /mnt/recoverybuild/30-source"
  echo "Run manually — add these lines near the top of main.rs:"
  cat << 'RUSTSNIP'
const I30LTZ_VERSION: &str = "v0.2.0-alpha";
const I30LTZ_BUILD_DATE: &str = "2026-10-06";
// Then in your Raylib window init:
// set_window_title(&format!("Dr. I30LTZ {} — {}", I30LTZ_VERSION, I30LTZ_BUILD_DATE));
RUSTSNIP
  exit 1
fi

echo "  Found: $MAIN_RS"

if grep -q "I30LTZ_VERSION" "$MAIN_RS"; then
  echo "SKIP: version constants already present in $MAIN_RS"
  exit 0
fi

# Backup
cp "$MAIN_RS" "${MAIN_RS}.bak-$(date +%Y%m%d-%H%M%S)"

# Inject version constants after the first 'use' block or at line 1
python3 - "$MAIN_RS" "$VERSION" "$BUILD_DATE" "$FIX_TAG" << 'PYEOF'
import sys, re

path, ver, bdate, tag = sys.argv[1:5]
code = open(path).read()

# Find last 'use ...' statement and insert constants after it
last_use = [(m.end()) for m in re.finditer(r'^use\s+[^;]+;\n', code, re.MULTILINE)]
if last_use:
    pos = last_use[-1]
else:
    pos = 0

insert = f"""
{tag}
const I30LTZ_VERSION: &str = "{ver}";
const I30LTZ_BUILD_DATE: &str = "{bdate}";

"""
patched = code[:pos] + insert + code[pos:]

# Replace any SetWindowTitle or set_window_title call with version-stamped version
# Handles: raylib::set_window_title("...") or SetWindowTitle(...)
def stamp_title(m):
    raw = m.group(0)
    # Already has version? skip
    if 'I30LTZ_VERSION' in raw:
        return raw
    fname = m.group(1)
    return f'{fname}(&format!("Dr. I30LTZ {{}} — {{}}", I30LTZ_VERSION, I30LTZ_BUILD_DATE))'

patched = re.sub(
    r'(set_window_title|SetWindowTitle)\s*\([^)]*\)',
    stamp_title,
    patched,
    flags=re.IGNORECASE
)

open(path, 'w').write(patched)
print(f"  Done: {path}")
PYEOF

echo "  Version constants added: I30LTZ_VERSION=\"$VERSION\" I30LTZ_BUILD_DATE=\"$BUILD_DATE\""
echo "  Any existing set_window_title() calls updated to include version stamp."
echo
echo "  Rebuild binary:"
echo "    cd $(dirname $MAIN_RS)/.. && cargo build --release"
echo "    # Signed SHA256 will change after rebuild — update in memory/docs"
