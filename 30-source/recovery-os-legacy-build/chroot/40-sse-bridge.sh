#!/usr/bin/env bash
# I30LTZ Recovery OS — Stage 40: SSE Bridge + Android companion service
# Version: 1.0.0  |  2026-09-25
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "DR. I30LTZ  |  40-sse-bridge.sh starting..."

# Install SSE bridge into OS
cp /tmp/sse-server/sse_bridge.py /opt/i30ltz/lib/sse_bridge.py
chmod +x /opt/i30ltz/lib/sse_bridge.py

# ── SSE Bridge systemd service ───────────────────────────────
cat > /etc/systemd/system/i30ltz-sse.service << 'EOF'
[Unit]
Description=DR. I30LTZ SSE Bridge — Android Companion Server
After=network-online.target madit.service
Wants=network-online.target

[Service]
Type=simple
User=dr-i30ltz
WorkingDirectory=/opt/i30ltz
ExecStart=/opt/i30ltz/venv/bin/python /opt/i30ltz/lib/sse_bridge.py
Restart=on-failure
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=SSE_PORT=7300
Environment=MADIT_URL=http://127.0.0.1:7301
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable i30ltz-sse.service

# Open firewall port for Android
ufw allow 7300/tcp comment "DR. I30LTZ Android SSE bridge" 2>/dev/null || true

# ── QR code generator (for Android pairing) ─────────────────
/opt/i30ltz/venv/bin/pip install qrcode[pil] -q 2>/dev/null || true

cat > /opt/i30ltz/scripts/show-pair-qr.sh << 'SCRIPT'
#!/usr/bin/env bash
# Show QR code for Android companion pairing
source /opt/i30ltz/venv/bin/activate
python3 - << 'PY'
import json, socket, subprocess, sys
from pathlib import Path

token_file = Path("/opt/i30ltz/config/sse_token")
if not token_file.exists():
    print("[DR. I30LTZ] SSE bridge not started yet — run: systemctl start i30ltz-sse")
    sys.exit(1)

token = token_file.read_text().strip()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.connect(("8.8.8.8", 80))
ip = s.getsockname()[0]
s.close()

payload = json.dumps({"type": "i30ltz_pair", "url": f"http://{ip}:7300", "token": token})
print(f"\n  DR. I30LTZ Android Pairing")
print(f"  URL:   http://{ip}:7300")
print(f"  Token: {token}")
print(f"  Scan QR code with I30LTZ Android app:\n")
try:
    import qrcode
    qr = qrcode.QRCode(border=1)
    qr.add_data(payload)
    qr.print_ascii(invert=True)
except ImportError:
    print(f"  [{payload}]")
    print("  (install qrcode package for visual QR)")
PY
SCRIPT
chmod +x /opt/i30ltz/scripts/show-pair-qr.sh

# Desktop shortcut for QR pairing
cat > /usr/local/share/applications/i30ltz-pair.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Pair Android App
Comment=Show QR code to connect I30LTZ Android companion
Exec=xfce4-terminal -e "/opt/i30ltz/scripts/show-pair-qr.sh; read"
Icon=network-wireless
Terminal=false
Categories=System;
EOF

echo "40-sse-bridge.sh ✓ complete"
