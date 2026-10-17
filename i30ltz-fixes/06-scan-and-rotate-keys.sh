#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# FIX C3 — Scan for leaked API keys + guide rotation
# I30LTZ Recovery OS · 2026-10-06
# Run on: i30ltz-x13-gen-1 as normal user
# WARNING: READ ONLY — does not modify any files
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCAN_ROOTS=(
  "/mnt/recoverybuild"
  "/mnt/Lucy/30-source"
  "/mnt/storage"
)

PATTERNS=(
  "sk-[a-zA-Z0-9-]{40,}"        # OpenAI keys
  "nvapi-[a-zA-Z0-9-]{32,}"     # NVIDIA keys
  "AIza[a-zA-Z0-9_-]{32,}"      # Google API keys
  "sk-or-v1-[a-zA-Z0-9-]{40,}"  # OpenRouter keys
)

SAFE_ENV="/mnt/Lucy/20-runtime/.env"

echo "=================================================================="
echo " I30LTZ API Key Leak Scanner · 2026-10-06"
echo " Scanning for live credentials outside the safe location"
echo "=================================================================="
echo ""

FOUND=0

for ROOT in "${SCAN_ROOTS[@]}"; do
  [[ -d "$ROOT" ]] || { echo "SKIP: $ROOT not mounted"; continue; }
  echo "Scanning $ROOT ..."

  for PATTERN in "${PATTERNS[@]}"; do
    MATCHES=$(grep -rn --include="*.py" --include="*.json" \
      --include="*.env" --include="*.ts" --include="*.js" \
      --include="*.cs" --include="*.sh" --include="*.yml" \
      --include="*.yaml" --include="*.toml" \
      -E "$PATTERN" "$ROOT" 2>/dev/null || true)

    if [[ -n "$MATCHES" ]]; then
      echo ""
      echo "  ⚠ FOUND ($PATTERN):"
      # Print file:line but mask the key value itself
      echo "$MATCHES" | while IFS= read -r line; do
        FILE=$(echo "$line" | cut -d: -f1)
        LINENO=$(echo "$line" | cut -d: -f2)
        # Show location but redact key
        REDACTED=$(echo "$line" | sed -E "s/$PATTERN/[REDACTED]/g")
        echo "    $REDACTED"
        FOUND=$((FOUND + 1))
      done
    fi
  done
done

echo ""
echo "=================================================================="
if [[ $FOUND -eq 0 ]]; then
  echo " ✓ No keys found outside safe locations. Good."
else
  echo " ✗ $FOUND key location(s) found. Rotate at each provider immediately."
  echo ""
  echo " ROTATION STEPS (do all three today — 11+ days exposed):"
  echo ""
  echo " 1. OPENAI: https://platform.openai.com/api-keys"
  echo "    → Delete old key → Create new → save ONLY to:"
  echo "    echo 'OPENAI_API_KEY=sk-new...' >> $SAFE_ENV"
  echo "    chmod 600 $SAFE_ENV"
  echo ""
  echo " 2. NVIDIA: https://build.nvidia.com/settings/api-keys"
  echo "    → Revoke old key → Generate new → same as above"
  echo "    echo 'NVIDIA_API_KEY=nvapi-new...' >> $SAFE_ENV"
  echo ""
  echo " 3. GOOGLE: https://console.cloud.google.com/apis/credentials"
  echo "    → Delete compromised key → Create new restricted key"
  echo "    echo 'GOOGLE_API_KEY=AIza-new...' >> $SAFE_ENV"
  echo ""
  echo " After rotation — remove from every location above except $SAFE_ENV"
  echo " Then run: bash /mnt/Lucy/70-scripts/scan-secrets.sh (if available)"
fi
echo "=================================================================="
