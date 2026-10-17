#!/usr/bin/env bash
# I30LTZ Recovery OS — Stage 60: Finalize + cleanup
# Version: 1.0.0  |  2026-09-25
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "DR. I30LTZ  |  60-finalize.sh starting..."

# ── Update initramfs ─────────────────────────────────────────
update-initramfs -u -k all

# ── Enable UFW ───────────────────────────────────────────────
ufw --force enable 2>/dev/null || true

# ── Regenerate machine-id for live ISO ───────────────────────
rm -f /etc/machine-id
dbus-uuidgen --ensure=/etc/machine-id

# ── Remove SSH host keys (regenerated on each boot) ──────────
rm -f /etc/ssh/ssh_host_*

# ── Live ISO casper setup ─────────────────────────────────────
cat > /etc/casper.conf << 'EOF'
export USERNAME="dr-i30ltz"
export USERFULLNAME="DR. I30LTZ"
export HOST="i30ltz-recovery"
export BUILD_SYSTEM="I30LTZ Recovery OS 1.0.0"
EOF

# ── MOTD ─────────────────────────────────────────────────────
cat > /etc/motd << 'EOF'

  ██╗██████╗  ██████╗ ██╗  ████████╗███████╗
  ██║╚════██╗██╔═══██╗██║  ╚══██╔══╝╚════██║
  ██║ █████╔╝██║   ██║██║     ██║       ██╔╝
  ██║ ╚═══██╗██║   ██║██║     ██║      ██╔╝
  ██║██████╔╝╚██████╔╝███████╗██║      ██║
  ╚═╝╚═════╝  ╚═════╝ ╚══════╝╚═╝      ╚═╝

  I30LTZ Recovery OS v1.0.0 (NIGHTFALL)  |  2026-09-25
  AI: DR. I30LTZ "MAD IT"
  ─────────────────────────────────────────────────────
  Services:  systemctl list-units --state=active
  AI Status: curl http://127.0.0.1:7301/api/version
  SSE Bridge: http://localhost:7300
  Pair Android: /opt/i30ltz/scripts/show-pair-qr.sh
  ─────────────────────────────────────────────────────

EOF

# ── /etc/issue ────────────────────────────────────────────────
echo "I30LTZ Recovery OS v1.0.0 (NIGHTFALL)  \\l" > /etc/issue

# ── Permission fix ───────────────────────────────────────────
chown -R dr-i30ltz:dr-i30ltz /home/dr-i30ltz/

# ── APT cleanup ──────────────────────────────────────────────
apt-get autoremove -y -qq
apt-get clean -qq
rm -rf /var/lib/apt/lists/* /tmp/chroot-scripts /tmp/i30ltz-config /tmp/sse-server

# ── Build manifest ───────────────────────────────────────────
cat > /opt/i30ltz/BUILD_INFO << EOF
OS_NAME=I30LTZ Recovery OS
OS_VERSION=1.0.0
OS_CODENAME=NIGHTFALL
BUILD_DATE=$(date +%Y-%m-%d)
BUILD_TS=$(date -Iseconds)
AI_NAME=DR. I30LTZ MAD IT
BASE=Ubuntu 24.04 LTS (noble)
DESKTOP=XFCE4
SSE_PORT=7300
MADIT_PORT=7301
EOF

echo "60-finalize.sh ✓ complete"
echo ""
echo "==== I30LTZ Recovery OS chroot build COMPLETE ===="
