#!/usr/bin/env bash
# setup-boltz-brain.sh
# Install and wire Mad Dr. Boltz SSE backend on Ubuntu
# Version: 0.1.0-alpha | Date: 2026-10-05
# Run: sudo bash setup-boltz-brain.sh
# -------------------------------------------------------

set -e
ROOT="/mnt/recoverybuild"
BRAIN="$ROOT/30-source/mad-dr-boltz/brain"
RUNTIME="$ROOT/20-runtime"

echo "[DR.BOLTZ] Setting up brain on Ubuntu..."

# 1. System deps
apt-get update -qq
apt-get install -y --no-install-recommends \
  python3 python3-pip python3-venv \
  curl ollama 2>/dev/null || true

# 2. Python venv
python3 -m venv "$BRAIN/venv"
"$BRAIN/venv/bin/pip" install -q --upgrade pip
"$BRAIN/venv/bin/pip" install -q -r "$BRAIN/requirements.txt"

# 3. Ollama model
echo "[DR.BOLTZ] Pulling qwen2.5:7b (may take a while on first run)..."
ollama pull qwen2.5:7b || echo "[WARN] Ollama not running — pull manually: ollama pull qwen2.5:7b"

# 4. Env file
if [ ! -f "$RUNTIME/.env.boltz" ]; then
  cp "$RUNTIME/.env.boltz.template" "$RUNTIME/.env.boltz"
  chmod 600 "$RUNTIME/.env.boltz"
  echo "[DR.BOLTZ] Created $RUNTIME/.env.boltz — edit BOLTZ_AUTH_TOKEN before prod"
fi

# 5. Recovery user
id recovery &>/dev/null || useradd -r -s /bin/false -d /mnt/recoverybuild recovery
chown -R recovery:recovery "$ROOT/30-source/mad-dr-boltz/brain"

# 6. Systemd service
cp "$RUNTIME/mad-dr-boltz.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable mad-dr-boltz
systemctl restart mad-dr-boltz

echo ""
echo "[DR.BOLTZ] ✅ Brain online"
echo "[DR.BOLTZ]    Status: systemctl status mad-dr-boltz"
echo "[DR.BOLTZ]    Logs:   journalctl -u mad-dr-boltz -f"
echo "[DR.BOLTZ]    Test:   curl -s -X POST http://localhost:5000/boltz \\"
echo "               -H 'X-Swarm-Auth: swarm-token-2026' \\"
echo "               -H 'Content-Type: application/json' \\"
echo "               -d '{\"message\":\"system status\"}'"
echo ""
echo "[DR.BOLTZ]    Then run the Rust binary:"
echo "             LUCY_URL=http://localhost:5000 ./mad-dr-boltz/recovery/bin/i30ltz-recovery"
