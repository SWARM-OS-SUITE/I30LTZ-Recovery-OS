#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# FIX C1 — Bake qwen2.5:7b into ISO (offline-first requirement)
# I30LTZ Recovery OS · 2026-10-06
# Run on: i30ltz-x13-gen-1 as normal user
# ─────────────────────────────────────────────────────────────
set -euo pipefail

BUILD_SCRIPT="/mnt/recoverybuild/70-scripts/build.sh"
MARKER="# [FIX-C1] I30LTZ_BAKE_MODEL set by 01-bake-model.sh 2026-10-06"

echo "==> [C1] Patching $BUILD_SCRIPT to bake model into ISO..."

if [[ ! -f "$BUILD_SCRIPT" ]]; then
  echo "ERROR: $BUILD_SCRIPT not found. Is /mnt/recoverybuild mounted?"
  exit 1
fi

# Idempotency check
if grep -q "I30LTZ_BAKE_MODEL=1" "$BUILD_SCRIPT"; then
  echo "SKIP: I30LTZ_BAKE_MODEL=1 already present in build.sh"
  exit 0
fi

# Backup
cp "$BUILD_SCRIPT" "${BUILD_SCRIPT}.bak-$(date +%Y%m%d-%H%M%S)"
echo "  Backup written."

# Insert after the shebang line (line 1) so it's set before any logic runs
sed -i "1a\\
$MARKER\\
export I30LTZ_BAKE_MODEL=1  # Bake qwen2.5:7b into ISO at build time (offline-first)" \
  "$BUILD_SCRIPT"

echo "  Done. I30LTZ_BAKE_MODEL=1 injected into $BUILD_SCRIPT"
echo
echo "  NOTE: Baking adds ~4 GB to ISO size and requires Ollama to be reachable"
echo "        on the build host (http://127.0.0.1:11434) when build.sh runs."
echo "  Next: sudo bash $BUILD_SCRIPT"
