#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
#  I30LTZ Recovery OS — MASTER FIX SCRIPT
#  Version: 1.0.0 · Date: 2026-10-06
#  Fixes all Critical + High issues from the 2026-10-06 daily audit
#  Run on: i30ltz-x13-gen-1 as your NORMAL USER (not root)
#  Source:  copy this entire i30ltz-fixes/ folder to your machine first
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/i30ltz-fixes-$(date +%Y%m%d-%H%M%S).log"
PASS=0; FAIL=0; SKIP=0

# ── Helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

header() { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }
ok()     { echo -e "${GREEN}  ✓ $1${RESET}"; ((PASS++)); }
warn()   { echo -e "${ORANGE}  ⚠ $1${RESET}"; ((SKIP++)); }
fail()   { echo -e "${RED}  ✗ $1${RESET}"; ((FAIL++)); }
step()   { echo -e "  → $1"; }

run_fix() {
  local num="$1" desc="$2" script="$3"
  header "FIX $num: $desc"
  if [[ -f "$SCRIPT_DIR/$script" ]]; then
    if bash "$SCRIPT_DIR/$script" 2>&1 | tee -a "$LOG_FILE"; then
      ok "$desc — complete"
    else
      fail "$desc — FAILED (check $LOG_FILE)"
    fi
  else
    fail "Script not found: $SCRIPT_DIR/$script"
  fi
}

# ── Pre-flight ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗"
echo -e "║  I30LTZ Recovery OS — Audit Fix Bundle  2026-10-06  ║"
echo -e "╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Logging to: $LOG_FILE"
echo ""

# Check mounts
for MOUNT in /mnt/recoverybuild /mnt/Lucy; do
  if mountpoint -q "$MOUNT" 2>/dev/null || [[ -d "$MOUNT" && "$(ls -A $MOUNT 2>/dev/null)" ]]; then
    ok "$MOUNT is accessible"
  else
    warn "$MOUNT not accessible — some fixes will be skipped"
  fi
done

# ── CRITICAL FIXES ────────────────────────────────────────────────────
header "CRITICAL FIXES (must complete before next build)"

run_fix "C1" "Bake qwen2.5:7b into ISO (offline-first)" "01-bake-model.sh"
run_fix "C3" "Scan for leaked API keys + rotation guide" "06-scan-and-rotate-keys.sh"
run_fix "C4" "Compile LucyServer security hardening" "05-compile-verify-lucy.sh"
run_fix "C5" "Mask tailscaled + sentinel in live ISO" "03-mask-live-services.sh"

# ── HIGH FIXES ────────────────────────────────────────────────────────
header "HIGH FIXES"

# H1: Boltz auth — find the server file
header "FIX H1: Add X-Swarm-Auth to boltz_server.py"
BOLTZ_CANDIDATES=(
  "/mnt/recoverybuild/30-source/mad-dr-boltz/brain/boltz_server.py"
  "/mnt/recoverybuild/30-source/mad-dr-boltz/boltz_server.py"
  "/opt/i30ltz/brain/boltz_server.py"
)
BOLTZ_FOUND=""
for f in "${BOLTZ_CANDIDATES[@]}"; do
  [[ -f "$f" ]] && { BOLTZ_FOUND="$f"; break; }
done

if [[ -n "$BOLTZ_FOUND" ]]; then
  step "Found boltz_server.py at: $BOLTZ_FOUND"
  if python3 "$SCRIPT_DIR/02-boltz-auth-patch.py" "$BOLTZ_FOUND" 2>&1 | tee -a "$LOG_FILE"; then
    ok "boltz_server.py auth hardened"
  else
    fail "boltz auth patch failed — check $LOG_FILE"
  fi
else
  warn "boltz_server.py not found at expected locations — patch it manually:"
  echo "       python3 $SCRIPT_DIR/02-boltz-auth-patch.py /path/to/boltz_server.py"
fi

# ── MEDIUM FIXES ──────────────────────────────────────────────────────
header "MEDIUM FIXES"
run_fix "M4" "Add version stamp to Raylib GUI title bar" "04-rust-version-stamp.sh"

# ── FIRST BOOT TEST ───────────────────────────────────────────────────
header "RUN BOOT TEST (required before any release)"
BOOT_TEST="/mnt/recoverybuild/80-vm/test-i30ltz.sh"
if [[ -f "$BOOT_TEST" ]]; then
  step "Boot test found at: $BOOT_TEST"
  echo -e "  ${BOLD}Run this now:${RESET}"
  echo "    bash $BOOT_TEST"
  warn "Boot test not auto-run (needs QEMU/KVM — run manually)"
else
  fail "Boot test script not found: $BOOT_TEST"
fi

# ── MANUAL ACTIONS REQUIRED ───────────────────────────────────────────
header "MANUAL ACTIONS STILL REQUIRED (cannot be scripted)"
echo ""
echo -e "  ${RED}${BOLD}1. ROTATE API KEYS${RESET} — 11+ days exposed, do this first:"
echo "     • OpenAI:  https://platform.openai.com/api-keys"
echo "     • NVIDIA:  https://build.nvidia.com/settings/api-keys"
echo "     • Google:  https://console.cloud.google.com/apis/credentials"
echo "     Write new keys ONLY to /mnt/Lucy/20-runtime/.env (chmod 600)"
echo ""
echo -e "  ${ORANGE}${BOLD}2. RUN BOOT TEST${RESET}:"
echo "     bash /mnt/recoverybuild/80-vm/test-i30ltz.sh"
echo ""
echo -e "  ${ORANGE}${BOLD}3. REBUILD ISO${RESET} (after all fixes applied):"
echo "     sudo bash /mnt/recoverybuild/70-scripts/build.sh"
echo ""
echo -e "  ${ORANGE}${BOLD}4. REBUILD RUST BINARY${RESET} (if Rust fix was applied):"
echo "     cd /mnt/recoverybuild/30-source/mad-dr-boltz && cargo build --release"
echo "     Update SHA256 in project docs after rebuild."

# ── SUMMARY ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo -e "  RESULTS: ${GREEN}${PASS} passed${RESET}  ${ORANGE}${SKIP} skipped${RESET}  ${RED}${FAIL} failed${RESET}"
echo -e "  Full log: $LOG_FILE"
echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo ""

[[ $FAIL -gt 0 ]] && exit 1 || exit 0
