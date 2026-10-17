#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# FIX C5 — Disable tailscaled + sentinel auto-enable in live ISO
# Creates a new live-build hook that masks both services
# I30LTZ Recovery OS · 2026-10-06
# Run on: i30ltz-x13-gen-1 as normal user (NO sudo needed to write hook)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

PROFILE_DIR="/mnt/recoverybuild/40-iso-profile"
HOOKS_DIR="$PROFILE_DIR/config/hooks/live"
HOOK_FILE="$HOOKS_DIR/0050-mask-live-services.hook.chroot"

echo "==> [C5] Writing service-mask hook for live ISO..."

if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "ERROR: $PROFILE_DIR not found. Is /mnt/recoverybuild mounted?"
  exit 1
fi

mkdir -p "$HOOKS_DIR"

if [[ -f "$HOOK_FILE" ]]; then
  echo "SKIP: $HOOK_FILE already exists"
  exit 0
fi

cat > "$HOOK_FILE" << 'HOOKEOF'
#!/bin/bash
# ISO Live Hook: mask network-exposing services in live session
# Date: 2026-10-06 | Source: [FIX-C5] i30ltz-fixes/03-mask-live-services.sh
# These services auto-enable on boot and expose the live machine to networks.
# A recovery disk should NEVER open remote access by default.

set -euo pipefail

echo "[i30ltz-hook] Masking tailscaled and sentinel in live session..."

systemctl mask tailscaled.service    2>/dev/null || true
systemctl mask sentinel.service      2>/dev/null || true
systemctl disable tailscaled.service 2>/dev/null || true
systemctl disable sentinel.service   2>/dev/null || true

# Also prevent socket activation if sockets exist
systemctl mask tailscaled.socket 2>/dev/null || true
systemctl mask sentinel.socket   2>/dev/null || true

# Drop any lingering wants symlinks
rm -f /etc/systemd/system/multi-user.target.wants/tailscaled.service
rm -f /etc/systemd/system/multi-user.target.wants/sentinel.service

echo "[i30ltz-hook] Done. tailscaled + sentinel are masked in the live environment."
echo "[i30ltz-hook] To access remotely in live: sudo systemctl unmask tailscaled && sudo systemctl start tailscaled"
HOOKEOF

chmod +x "$HOOK_FILE"
echo "  Written: $HOOK_FILE"
echo
echo "  IMPORTANT: This masks the services in the built ISO's live session."
echo "  Services remain available if the user explicitly unmasks them after booting."
echo "  Rebuild required for this to take effect:"
echo "    sudo bash /mnt/recoverybuild/70-scripts/build.sh"
