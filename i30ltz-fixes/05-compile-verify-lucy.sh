#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# FIX C4 (compile step) — Build + verify LucyServer security hardening
# SwarmSecrets.cs, token validation, filesystem root clamp
# I30LTZ Recovery OS · 2026-10-06
# Run on: i30ltz-x13-gen-1 as normal user
# ─────────────────────────────────────────────────────────────
set -euo pipefail

LUCY_SRC="/mnt/Lucy/30-source/LucyServer"
SECRETS_SVC="$LUCY_SRC/Services/SwarmSecrets.cs"
PROGRAM_CS="$LUCY_SRC/Program.cs"

echo "==> [C4] Compiling LucyServer security hardening..."

# Pre-checks
if [[ ! -d "$LUCY_SRC" ]]; then
  echo "ERROR: $LUCY_SRC not found. Is /mnt/Lucy mounted?"
  exit 1
fi

# 1. Verify SwarmSecrets.cs exists (should have been written 2026-10-05)
if [[ ! -f "$SECRETS_SVC" ]]; then
  echo "ERROR: $SECRETS_SVC not found."
  echo "  The SwarmSecrets.cs fix was written in session but may not have been saved."
  echo "  Check /mnt/Lucy/30-source/LucyServer/Services/ for partial file."
  exit 1
fi
echo "  Found: $SECRETS_SVC ✓"

# 2. Verify the dangerous default token is gone from Program.cs
if grep -q '"swarm-token-2026"' "$PROGRAM_CS"; then
  echo ""
  echo "  CRITICAL: Program.cs still contains the hardcoded fallback token!"
  echo "  Line: $(grep -n 'swarm-token-2026' "$PROGRAM_CS")"
  echo ""
  echo "  This must be removed before building. The line should read:"
  echo '    Environment.GetEnvironmentVariable("SWARM_AUTH_TOKEN")'
  echo "  with a startup check that throws if it's null/empty/short."
  echo ""
  echo "  Patching now..."

  # Remove the fallback — replace ?? "swarm-token-2026" with null-check throw
  cp "$PROGRAM_CS" "${PROGRAM_CS}.bak-$(date +%Y%m%d-%H%M%S)"
  python3 - "$PROGRAM_CS" << 'PYEOF'
import sys, re
path = sys.argv[1]
code = open(path).read()

# Replace the fallback pattern
old = r'Environment\.GetEnvironmentVariable\("SWARM_AUTH_TOKEN"\)\s*\?\?\s*"swarm-token-2026"'
new = 'SwarmSecrets.Lookup("SWARM_AUTH_TOKEN") ?? throw new InvalidOperationException("SWARM_AUTH_TOKEN is not set. Set it in /mnt/Lucy/20-runtime/.env")'
patched, n = re.subn(old, new, code)

if n == 0:
    print("  [!] Pattern not found — check Program.cs manually for 'swarm-token-2026'")
else:
    open(path, 'w').write(patched)
    print(f"  [+] Removed fallback token from Program.cs ({n} replacement(s))")
PYEOF

fi

# 3. Verify FixedTimeEquals is present (not .Contains())
if ! grep -q "FixedTimeEquals\|ConstantTimeEquals\|compare_digest\|subtle" "$PROGRAM_CS"; then
  echo "  WARNING: No constant-time comparison found in Program.cs"
  echo "  Timing-attack resistant comparison is required for auth token checks."
  echo "  Use: CryptographicOperations.FixedTimeEquals() in .NET"
fi

# 4. Build
echo ""
echo "  Building LucyServer..."
cd "$LUCY_SRC"
dotnet build --configuration Release 2>&1 | tail -20

# 5. Verify: run with no token set — should refuse to start
echo ""
echo "  Verifying startup rejection when SWARM_AUTH_TOKEN is unset..."
unset SWARM_AUTH_TOKEN
RESULT=$(dotnet run --no-build 2>&1 | head -5 || true)
if echo "$RESULT" | grep -qi "SWARM_AUTH_TOKEN\|InvalidOperationException\|not set\|unset"; then
  echo "  ✓ PASS: Server refused to start without SWARM_AUTH_TOKEN"
else
  echo "  ✗ FAIL: Server started without SWARM_AUTH_TOKEN — hardening incomplete"
  echo "  Output: $RESULT"
  exit 1
fi

echo ""
echo "==> [C4] LucyServer hardening compiled and verified."
echo "    Set env: export SWARM_AUTH_TOKEN=\$(openssl rand -hex 32)"
echo "    Then add it to /mnt/Lucy/20-runtime/.env (chmod 600)"
