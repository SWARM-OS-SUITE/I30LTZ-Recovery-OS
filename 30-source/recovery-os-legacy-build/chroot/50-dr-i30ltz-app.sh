#!/usr/bin/env bash
# I30LTZ Recovery OS — Stage 50: Install DR. I30LTZ Recovery Rust app
# Version: 1.0.0  |  2026-09-25
# Installs the compiled i30ltz-recovery binary + assets
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "DR. I30LTZ  |  50-dr-i30ltz-app.sh starting..."

# Raylib runtime deps
apt-get install -y --no-install-recommends \
  libgl1-mesa-dri libgl1-mesa-glx mesa-utils \
  libgles2-mesa libgles2 \
  libx11-6 libxrandr2 libxinerama1 libxcursor1 libxi6 \
  libxfixes3 libxext6

# ── DR. I30LTZ app directories ───────────────────────────────
mkdir -p /opt/i30ltz/bin
mkdir -p /opt/i30ltz/assets

# Binary placeholder — sync_lucille_ai.sh places the actual binary
# At build time the binary is expected at: /tmp/i30ltz-recovery
if [[ -f "/tmp/i30ltz-recovery" ]]; then
  cp /tmp/i30ltz-recovery /opt/i30ltz/bin/i30ltz-recovery
  chmod +x /opt/i30ltz/bin/i30ltz-recovery
  echo "  ✓ Binary installed from /tmp/i30ltz-recovery"
else
  # Create a placeholder launch script that builds from source if binary missing
  cat > /opt/i30ltz/bin/i30ltz-recovery << 'LAUNCH'
#!/usr/bin/env bash
BINARY="/opt/i30ltz/bin/i30ltz-recovery.real"
if [[ -f "$BINARY" ]]; then
  exec "$BINARY" "$@"
fi
# Try boltz drive
BOLTZ_BIN="/mnt/boltz/I30LTZ-Recovery/i30ltz-recovery"
if [[ -f "$BOLTZ_BIN" ]]; then
  exec "$BOLTZ_BIN" "$@"
fi
xfce4-terminal -e "bash -c 'echo DR. I30LTZ binary not found. Mount boltz drive or rebuild.; read'"
LAUNCH
  chmod +x /opt/i30ltz/bin/i30ltz-recovery
  echo "  ⚠ Binary placeholder installed (mount boltz or rebuild)"
fi

# ── Symlink to PATH ──────────────────────────────────────────
ln -sf /opt/i30ltz/bin/i30ltz-recovery /usr/local/bin/i30ltz-recovery

# ── systemd autostart for DR. I30LTZ Recovery GUI ───────────
cat > /etc/systemd/system/dr-i30ltz-recovery.service << 'EOF'
[Unit]
Description=DR. I30LTZ Recovery — AI Evaluation GUI
After=graphical.target i30ltz-sse.service madit.service
Requires=graphical.target

[Service]
Type=simple
User=dr-i30ltz
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/dr-i30ltz/.Xauthority
Environment=LUCY_URL=http://127.0.0.1:7301
Environment=SWARM_AUTH_TOKEN=i30ltz-2026
ExecStartPre=/bin/sleep 5
ExecStart=/opt/i30ltz/bin/i30ltz-recovery
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical.target
EOF

# ── XFCE autostart entry ─────────────────────────────────────
mkdir -p /home/dr-i30ltz/.config/autostart
cat > /home/dr-i30ltz/.config/autostart/dr-i30ltz-recovery.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=DR. I30LTZ Recovery
Exec=/opt/i30ltz/bin/i30ltz-recovery
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# ── Status bar / notification helper ────────────────────────
cat > /opt/i30ltz/scripts/status-notify.sh << 'SCRIPT'
#!/usr/bin/env bash
# DR. I30LTZ — send desktop notification on service events
export DISPLAY=:0
export XAUTHORITY=/home/dr-i30ltz/.Xauthority
MSG="${1:-DR. I30LTZ event}"
ICON="${2:-dialog-information}"
dunstify -i "$ICON" "DR. I30LTZ" "$MSG" -t 5000 2>/dev/null || \
  notify-send "DR. I30LTZ" "$MSG" 2>/dev/null || true
SCRIPT
chmod +x /opt/i30ltz/scripts/status-notify.sh

chown -R dr-i30ltz:dr-i30ltz /opt/i30ltz 2>/dev/null || true
chown -R dr-i30ltz:dr-i30ltz /home/dr-i30ltz/ 2>/dev/null || true

echo "50-dr-i30ltz-app.sh ✓ complete"
