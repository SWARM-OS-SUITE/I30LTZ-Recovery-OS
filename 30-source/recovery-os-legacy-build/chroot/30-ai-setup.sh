#!/usr/bin/env bash
# I30LTZ Recovery OS — Stage 30: DR. I30LTZ "MAD IT" AI Stack
# Version: 1.0.0  |  2026-09-25
# Stack: Ollama + 7B model + Python inference API
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "DR. I30LTZ  |  30-ai-setup.sh starting..."

# ── Python AI deps ───────────────────────────────────────────
apt-get install -y --no-install-recommends \
  python3-full python3-pip python3-venv \
  python3-dev \
  build-essential \
  libssl-dev libffi-dev

# ── DR. I30LTZ Python venv ───────────────────────────────────
mkdir -p /opt/i30ltz/{bin,lib,assets,models,logs,config}
python3 -m venv /opt/i30ltz/venv

/opt/i30ltz/venv/bin/pip install --upgrade pip wheel -q
/opt/i30ltz/venv/bin/pip install \
  fastapi uvicorn[standard] \
  sse-starlette \
  httpx aiohttp \
  pydantic \
  psutil \
  py-cpuinfo \
  sqlalchemy \
  click \
  rich -q

echo "Python AI venv ready at /opt/i30ltz/venv"

# ── Ollama install script (runs on first boot) ────────────────
# (Ollama binaries need network; deferred to first-boot service)
cat > /opt/i30ltz/scripts/install-ollama.sh << 'SCRIPT'
#!/usr/bin/env bash
# First-boot: install Ollama + pull MAD IT model
set -euo pipefail
echo "[MAD IT] Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh
systemctl enable --now ollama
sleep 3
echo "[MAD IT] Pulling mistral:7b (or available 7B)..."
ollama pull mistral:7b || ollama pull llama3.2:3b
echo "[MAD IT] AI stack ready."
systemctl disable i30ltz-first-boot.service
SCRIPT
chmod +x /opt/i30ltz/scripts/install-ollama.sh

# ── First-boot systemd service ───────────────────────────────
cat > /etc/systemd/system/i30ltz-first-boot.service << 'EOF'
[Unit]
Description=DR. I30LTZ First Boot Setup (Ollama + AI Model)
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/opt/i30ltz/.ollama-installed

[Service]
Type=oneshot
ExecStart=/opt/i30ltz/scripts/install-ollama.sh
ExecStartPost=/bin/touch /opt/i30ltz/.ollama-installed
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable i30ltz-first-boot.service

# ── MAD IT inference config ──────────────────────────────────
cat > /opt/i30ltz/config/madit.json << 'EOF'
{
  "name": "DR. I30LTZ MAD IT",
  "version": "1.0.0",
  "build_date": "2026-09-25",
  "ollama_url": "http://127.0.0.1:11434",
  "preferred_model": "mistral:7b",
  "fallback_model": "llama3.2:3b",
  "max_context": 4096,
  "system_prompt": "You are DR. I30LTZ, an expert AI recovery and diagnostic assistant. You specialize in OS recovery, disk rescue, boot repair, hardware diagnostics, and system optimization. You are concise, technical, and precise. When given system telemetry, you analyze it and suggest actionable fixes. You always prioritize data safety and user security.",
  "sse_port": 7300,
  "api_port": 7301,
  "log_path": "/opt/i30ltz/logs/madit.log"
}
EOF

# ── MAD IT inference server ──────────────────────────────────
cat > /opt/i30ltz/lib/madit_server.py << 'EOF'
#!/usr/bin/env python3
"""
DR. I30LTZ MAD IT — AI Inference + SSE Server
Version: 1.0.0  |  2026-09-25
Handles: chat, system telemetry analysis, command suggestions
"""
import asyncio
import json
import logging
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import AsyncGenerator, Optional

import httpx
import psutil
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

CONFIG_PATH = Path("/opt/i30ltz/config/madit.json")
LOG_PATH = Path("/opt/i30ltz/logs/madit.log")
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [MAD-IT] %(levelname)s: %(message)s",
    handlers=[
        logging.FileHandler(LOG_PATH),
        logging.StreamHandler()
    ]
)
log = logging.getLogger("madit")

with open(CONFIG_PATH) as f:
    CFG = json.load(f)

app = FastAPI(
    title="DR. I30LTZ MAD IT",
    description="AI Recovery & Diagnostic Server",
    version=CFG["version"]
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Telemetry ─────────────────────────────────────────────────
def get_telemetry() -> dict:
    """Collect live system telemetry."""
    try:
        temps = {}
        raw = psutil.sensors_temperatures()
        for k, v in (raw or {}).items():
            temps[k] = [{"label": e.label, "current": e.current, "high": e.high} for e in v]
    except Exception:
        temps = {}

    disks = []
    for part in psutil.disk_partitions(all=False):
        try:
            usage = psutil.disk_usage(part.mountpoint)
            disks.append({
                "device": part.device,
                "mountpoint": part.mountpoint,
                "fstype": part.fstype,
                "total_gb": round(usage.total / 1e9, 1),
                "used_gb": round(usage.used / 1e9, 1),
                "free_gb": round(usage.free / 1e9, 1),
                "percent": usage.percent
            })
        except Exception:
            pass

    net = psutil.net_io_counters()
    mem = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=0.1)

    return {
        "timestamp": datetime.now().isoformat(),
        "hostname": os.uname().nodename,
        "uptime_s": int(time.time() - psutil.boot_time()),
        "cpu_percent": cpu,
        "cpu_count": psutil.cpu_count(),
        "memory": {
            "total_gb": round(mem.total / 1e9, 1),
            "used_gb": round(mem.used / 1e9, 1),
            "available_gb": round(mem.available / 1e9, 1),
            "percent": mem.percent
        },
        "disks": disks,
        "temperatures": temps,
        "network": {
            "bytes_sent": net.bytes_sent,
            "bytes_recv": net.bytes_recv
        }
    }

# ── Ollama client ─────────────────────────────────────────────
async def stream_ollama(prompt: str, system: Optional[str] = None) -> AsyncGenerator[str, None]:
    """Stream responses from local Ollama."""
    payload = {
        "model": CFG["preferred_model"],
        "prompt": prompt,
        "stream": True,
        "options": {"num_ctx": CFG["max_context"]}
    }
    if system:
        payload["system"] = system

    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream(
            "POST",
            f"{CFG['ollama_url']}/api/generate",
            json=payload
        ) as resp:
            if resp.status_code != 200:
                yield f"[MAD IT ERROR] Ollama returned {resp.status_code}"
                return
            async for line in resp.aiter_lines():
                if line:
                    try:
                        data = json.loads(line)
                        if token := data.get("response"):
                            yield token
                        if data.get("done"):
                            break
                    except json.JSONDecodeError:
                        pass

# ── Models ────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    message: str
    include_telemetry: bool = False
    session_id: Optional[str] = None

class AnalyzeRequest(BaseModel):
    telemetry: Optional[dict] = None
    focus: str = "general"  # general|disk|memory|network|boot

# ── Routes ────────────────────────────────────────────────────
@app.get("/api/version")
async def version():
    return {
        "name": CFG["name"],
        "version": CFG["version"],
        "build_date": CFG["build_date"],
        "model": CFG["preferred_model"],
        "status": "online"
    }

@app.get("/api/telemetry")
async def telemetry():
    return get_telemetry()

@app.post("/api/chat")
async def chat(req: ChatRequest):
    """Stream AI chat response as SSE."""
    system = CFG["system_prompt"]
    prompt = req.message

    if req.include_telemetry:
        tel = get_telemetry()
        prompt = f"System telemetry:\n{json.dumps(tel, indent=2)}\n\nUser: {req.message}"

    async def event_generator():
        async for token in stream_ollama(prompt, system):
            yield {"data": json.dumps({"token": token, "done": False})}
        yield {"data": json.dumps({"token": "", "done": True})}

    return EventSourceResponse(event_generator())

@app.post("/api/analyze")
async def analyze(req: AnalyzeRequest):
    """Analyze system telemetry and return AI diagnosis."""
    tel = req.telemetry or get_telemetry()
    focus_prompts = {
        "general": "Analyze this system telemetry and identify any issues. Provide a prioritized list of recommendations.",
        "disk": "Focus on disk health, usage, and any filesystem issues in this telemetry.",
        "memory": "Analyze memory usage patterns and identify potential memory issues.",
        "network": "Analyze network telemetry for issues or anomalies.",
        "boot": "Identify any boot-related issues based on this system state."
    }
    prompt = f"{focus_prompts.get(req.focus, focus_prompts['general'])}\n\nTelemetry:\n{json.dumps(tel, indent=2)}"

    async def event_generator():
        async for token in stream_ollama(prompt, CFG["system_prompt"]):
            yield {"data": json.dumps({"token": token, "done": False})}
        yield {"data": json.dumps({"token": "", "done": True})}

    return EventSourceResponse(event_generator())

@app.get("/health")
async def health():
    return {"status": "ok", "timestamp": datetime.now().isoformat()}

if __name__ == "__main__":
    import uvicorn
    log.info(f"Starting DR. I30LTZ MAD IT v{CFG['version']} on port {CFG['api_port']}")
    uvicorn.run(app, host="0.0.0.0", port=CFG["api_port"], log_level="info")
EOF

chmod +x /opt/i30ltz/lib/madit_server.py

# ── MAD IT systemd service ───────────────────────────────────
cat > /etc/systemd/system/madit.service << 'EOF'
[Unit]
Description=DR. I30LTZ MAD IT — AI Inference Server
After=ollama.service network.target
Requires=ollama.service

[Service]
Type=simple
User=dr-i30ltz
WorkingDirectory=/opt/i30ltz
ExecStart=/opt/i30ltz/venv/bin/python /opt/i30ltz/lib/madit_server.py
Restart=on-failure
RestartSec=5
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable madit.service

echo "30-ai-setup.sh ✓ complete"
