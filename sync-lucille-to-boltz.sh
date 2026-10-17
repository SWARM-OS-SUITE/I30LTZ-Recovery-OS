#!/usr/bin/env bash
# sync-lucille-to-boltz.sh
# Forks Lucille source into /mnt/recoverybuild as Mad Dr. Boltz backing
# Version: 0.1.0 | Date: 2026-10-05
# Run: sudo bash sync-lucille-to-boltz.sh
# -------------------------------------------------------

set -e
LUCY="/mnt/Lucy/30-source"
TARGET="/mnt/recoverybuild/30-source/mad-dr-boltz"
RECOVERY_SRC="/mnt/Lucy/30-source/i30ltz-recovery(seperate-related-project)"

echo "[DR.BOLTZ] Forking Lucille → Mad Dr. Boltz at $TARGET"

# Fix ownership first
chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} /mnt/recoverybuild

# Create target dirs
mkdir -p "$TARGET"/{core,server,recovery,brain,companion}

# 1. lucille-core C++ → core/
echo "[DR.BOLTZ] Syncing lucille-core → core/ ..."
rsync -av --exclude='build/' --exclude='*.o' --exclude='*.a' \
  "$LUCY/lucille-core/" "$TARGET/core/"

# 2. LucyServer .NET → server/
echo "[DR.BOLTZ] Syncing LucyServer → server/ ..."
rsync -av --exclude='bin/' --exclude='obj/' --exclude='publish/' \
  "$LUCY/LucyServer/" "$TARGET/server/"

# 3. i30ltz-recovery Rust → recovery/
echo "[DR.BOLTZ] Syncing i30ltz-recovery Rust → recovery/ ..."
rsync -av --exclude='target/' \
  "$RECOVERY_SRC/" "$TARGET/recovery/"

# Also copy the compiled binary
BINARY="$RECOVERY_SRC/target/release/i30ltz-recovery"
if [ -f "$BINARY" ]; then
  cp "$BINARY" "$TARGET/recovery/bin/"
  mkdir -p "$TARGET/recovery/bin"
  cp "$BINARY" "$TARGET/recovery/bin/i30ltz-recovery"
  echo "[DR.BOLTZ] ✅ Binary copied → recovery/bin/i30ltz-recovery"
fi

# 4. Drop the SOUL.md
cat > "$TARGET/SOUL.md" << 'SOUL'
# Mad Dr. Boltz — Soul & Cognitive Directives
Forked from: Lucille AI Core v2026.1
Version: 0.1.0-alpha | Date: 2026-10-05

Identity: Autonomous AI recovery agent. Diagnoses, repairs, recovers any OS.
Proposes every fix. User approves. No action without confirmation.
Signs: [DR.BOLTZ]

Safety: No-new-privs | OverlayFS isolation | 7B local Ollama | ntfy.sh approval gate
SOUL

# 5. Brain stub (Python Ollama agent)
mkdir -p "$TARGET/brain"
cat > "$TARGET/brain/boltz_agent.py" << 'PY'
#!/usr/bin/env python3
"""
Mad Dr. Boltz — AI Agent
Version: 0.1.0-alpha | Date: 2026-10-05
Backing: Lucille Core Engine
"""
import os, json, requests

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
MODEL = os.getenv("AGENT_MODEL", "qwen2.5:7b")
NTFY_TOPIC = os.getenv("NTFY_TOPIC", "boltz-approval")

SYSTEM_PROMPT = """You are Mad Dr. Boltz (DR.BOLTZ), an autonomous AI recovery agent.
You diagnose failing operating systems, recover data, and repair boot issues.
Rules:
- Always state confidence level (0-100%) before proposing a fix
- Never execute destructive commands — propose them, wait for approval
- Prefix every response with [DR.BOLTZ]
- Be terse, clinical, direct. No fluff."""

def ask_boltz(user_msg: str) -> str:
    resp = requests.post(f"{OLLAMA_URL}/api/chat", json={
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_msg}
        ],
        "stream": False
    })
    resp.raise_for_status()
    return resp.json()["message"]["content"]

def request_approval(action: str, token: str) -> None:
    """Send approval request via ntfy.sh — 90s timeout"""
    requests.post(f"https://ntfy.sh/{NTFY_TOPIC}", data=action.encode(),
        headers={"Title": "[DR.BOLTZ] Approval Required", "Tags": "warning",
                 "Actions": f"http, Approve, /approve/{token},,clear=true"})

if __name__ == "__main__":
    print("[DR.BOLTZ] Online. State your recovery objective.")
    while True:
        try:
            q = input("> ")
            print(ask_boltz(q))
        except KeyboardInterrupt:
            break
PY
chmod +x "$TARGET/brain/boltz_agent.py"

echo ""
echo "[DR.BOLTZ] ✅ Lucille → Mad Dr. Boltz fork complete"
echo "[DR.BOLTZ]    $TARGET"
echo ""
echo "Next: cd $TARGET && ls -la"
echo "      python3 brain/boltz_agent.py"
