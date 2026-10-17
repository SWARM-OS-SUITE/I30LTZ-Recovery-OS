#!/usr/bin/env bash
# I30LTZ Recovery OS — Project Scaffold Init
# Version: 0.2.0-alpha | Date: 2026-10-05
# Base OS: Ubuntu (live-build / casper)
# Run: sudo bash init-recoverybuild.sh
# ----------------------------------------

set -e
ROOT="/mnt/recoverybuild"

echo "[I30LTZ] Scaffolding $ROOT ..."

# Fix ownership
chown -R $SUDO_USER:$SUDO_USER "$ROOT" 2>/dev/null || true

# Create directory tree
for d in \
  00-CURRENT \
  10-releases \
  20-runtime \
  30-source/ubiso \
  30-source/mad-dr-boltz/brain \
  30-source/mad-dr-boltz/recovery/bin \
  30-source/enterprise-app \
  30-source/companion-app \
  40-iso-profile/config/hooks/live \
  40-iso-profile/config/hooks/normal \
  40-iso-profile/config/includes.chroot/etc/skel \
  40-iso-profile/config/includes.chroot/usr/local/bin \
  40-iso-profile/config/includes.chroot/etc/systemd/system \
  40-iso-profile/config/package-lists \
  40-iso-profile/config/preseed \
  50-backends \
  60-brain/agents \
  70-scripts \
  80-vm \
  90-docs \
  99-archive; do
  mkdir -p "$ROOT/$d"
done

# VERSION
cat > "$ROOT/VERSION" << 'EOF'
0.2.0-alpha-2026-10-05
EOF

# .gitignore
cat > "$ROOT/.gitignore" << 'EOF'
# I30LTZ Recovery OS — .gitignore | v0.2.0 | 2026-10-05
*.iso
*.img
*.bin
*.squashfs
10-releases/
80-vm/*.qcow2
99-archive/
*.log
build-tmp/
chroot/
binary/
cache/
.env
.env.local
*.pem
*.key
*.crt
client_secret_*.json
__pycache__/
*.pyc
.venv/
venv/
node_modules/
.next/
dist/
*.apk
*.aab
.gradle/
build/
target/
lost+found/
.Trash-*/
EOF

# README
cat > "$ROOT/README.md" << 'EOF'
# I30LTZ RECOVERY OS
**Version:** 0.2.0-alpha | **Date:** 2026-10-05 | **Build Root:** /mnt/recoverybuild
**Base OS:** Ubuntu (live-build / casper)

Ubuntu-based AI-native recovery OS with integrated diagnostics, data recovery,
OS repair, and telemetry. AI: **Mad Dr. Boltz ("THE MAD DR.")** — local Ollama 7B.

## Directory Layout
```
/mnt/recoverybuild/
├── 00-CURRENT/          # Active build state
├── 10-releases/         # Stamped ISO releases
├── 20-runtime/          # fstab, services, env (.env.boltz)
├── 30-source/
│   ├── ubiso/           # Ubuntu live-build chroot hooks (extra)
│   ├── mad-dr-boltz/    # Mad Dr. Boltz AI backend (SSE, Ollama)
│   │   ├── brain/       # Flask/Waitress Python SSE server
│   │   └── recovery/    # Rust/Raylib GUI binary (i30ltz-recovery)
│   ├── enterprise-app/  # Electron/Next.js repair UI
│   └── companion-app/   # Android Kotlin SSE companion
├── 40-iso-profile/      # Ubuntu live-build lb config tree
│   └── config/
│       ├── hooks/       # live/ and normal/ chroot hooks
│       ├── includes.chroot/  # Files overlaid into chroot
│       └── package-lists/   # APT package lists
├── 50-backends/         # Ollama model configs
├── 60-brain/            # MAD AI agents
├── 70-scripts/          # build.sh, install.sh, recover.sh
├── 80-vm/               # QEMU test configs
├── 90-docs/             # Architecture & runbooks
└── 99-archive/          # Old builds / backups
```

## Quick Start
```bash
# 1. Fix ownership (one time)
sudo chown -R $USER:$USER /mnt/recoverybuild

# 2. Run scaffold (creates dirs, git init, first commit)
sudo bash /mnt/recoverybuild/70-scripts/init-recoverybuild.sh

# 3. Set up Mad Dr. Boltz AI backend
sudo bash /mnt/recoverybuild/70-scripts/setup-boltz-brain.sh

# 4. Build ISO
sudo bash /mnt/recoverybuild/70-scripts/build.sh
```

## Wire Diagram
```
Rust binary (Raylib GUI, LUCY_URL=http://127.0.0.1:5000)
  └─ POST /boltz + X-Swarm-Auth header
       └─ boltz_server.py (Flask/Waitress :5000)
            └─ stream_ollama() → qwen2.5:7b via Ollama :11434
                 └─ SSE: data: {chunk}\\n\\n ... data: [DONE]\\n\\n
                      └─ Rust reads → renders in Chat tab

Android companion ──GET /sse/events──► heartbeat every 15s
```
EOF

# CLAUDE.md
cat > "$ROOT/CLAUDE.md" << 'EOF'
# I30LTZ RECOVERY OS — Claude Code Context
**Version:** 0.2.0-alpha | **Date:** 2026-10-05

## Identity
- OS: I30LTZ Recovery OS (codename: MAD AI)
- AI: Mad Dr. Boltz ("THE MAD DR.") — local Ollama, 7B max, qwen2.5:7b
- Base: Ubuntu (live-build / casper)
- Build Root: /mnt/recoverybuild
- Build Output: /mnt/recoverybuild/10-releases/
- Install Root: /mnt/recoveryos

## Hardware Target
- Integrated graphics only (no dGPU)
- 7B max LLM (qwen2.5:7b)
- Must run with ZERO external drives required
- Minimum: 4GB RAM, 8GB boot media

## Key Paths
- ISO profile:       40-iso-profile/
- AI backend:        30-source/mad-dr-boltz/brain/   (Flask SSE :5000)
- Rust GUI binary:   30-source/mad-dr-boltz/recovery/ (Raylib 1440x900)
- Enterprise app:    30-source/enterprise-app/
- Android companion: 30-source/companion-app/
- Build scripts:     70-scripts/
- AI brain:          60-brain/
- Systemd service:   20-runtime/mad-dr-boltz.service
- Env config:        20-runtime/.env.boltz

## SSE Protocol
- Endpoint: POST /boltz
- Auth: X-Swarm-Auth: $BOLTZ_AUTH_TOKEN
- Env: LUCY_URL (default http://127.0.0.1:5000)
- SSE format: data: {chunk}\n\n ... data: [DONE]\n\n

## Rules
- No hardcoded credentials in code — env file only
- No open sshd by default
- Tailscale-only remote access
- All AI destructive actions require explicit user approval before exec
- Approval gate: ntfy.sh → /approve/<token> (90s timeout)
EOF

# Build state
cat > "$ROOT/00-CURRENT/BUILD_STATE.md" << 'EOF'
# Build State — I30LTZ Recovery OS
**Version:** 0.2.0-alpha | **Date:** 2026-10-05 | **Status:** BRAIN WIRED

| Item | Status | Notes |
|------|--------|-------|
| Directory scaffold | ✅ DONE | 2026-10-05 v0.2.0 |
| CLAUDE.md / README | ✅ DONE | Ubuntu base |
| Mad Dr. Boltz SSE backend | ✅ DONE | boltz_server.py Flask/Waitress :5000 |
| Rust GUI binary (i30ltz-recovery) | ✅ DONE | Raylib 1440x900, reads SSE |
| SSE wire (Rust ↔ Python ↔ Ollama) | ✅ DONE | qwen2.5:7b |
| systemd service (mad-dr-boltz) | ✅ DONE | 20-runtime/ |
| setup-boltz-brain.sh | ✅ DONE | 70-scripts/ |
| Lucille fork → mad-dr-boltz | ✅ DONE | SOUL.md, requirements.txt |
| Ubuntu live-build ISO profile | 🔄 IN PROGRESS | 40-iso-profile/ |
| Enterprise repair app | 🔴 TODO | 30-source/enterprise-app/ |
| Android companion | 🔴 TODO | 30-source/companion-app/ |
| build.sh | 🔴 TODO | 70-scripts/ |
| Ollama model config | 🔴 TODO | 50-backends/ |
| AI brain / agents | 🔴 TODO | 60-brain/ |
| First ISO build & test | 🔴 TODO | 10-releases/ |
EOF

# Git init
cd "$ROOT"
git init -q
git add .
git commit -q -m "chore: scaffold v0.2.0 — Ubuntu base, Mad Dr. Boltz wired

- Ubuntu live-build base (replaces Debian)
- mad-dr-boltz SSE backend wired (Flask/Waitress :5000)
- Rust i30ltz-recovery GUI reads SSE from /boltz
- systemd service + setup script included
- 40-iso-profile/ structure ready for lb config
$(date -u +%Y-%m-%dT%H:%M:%SZ)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YLFqX3or6JKhVYrexHQ1GM"

echo ""
echo "[I30LTZ] ✅ Scaffold v0.2.0 complete at $ROOT"
echo "[I30LTZ]    Next: sudo bash $ROOT/70-scripts/setup-boltz-brain.sh"
echo "[I30LTZ]    Then: sudo bash $ROOT/70-scripts/build.sh"
