#!/usr/bin/env python3
"""
Mad Dr. Boltz — Unified SSE Backend Server
Version: 1.1.0 | Date: 2026-10-14
Base OS: Debian 13 (Trixie) Recovery OS

Merged per RC-10:
The legacy Flask backend in mad-dr-boltz has been unified into the canonical
FastAPI SSE bridge (mad-dr-ai/sse-server/sse_bridge.py).
This file provides full backward compatibility for any script, systemd service,
or test expecting boltz_server.py.

Supported Endpoints:
  POST /boltz           → SSE chat stream (i30ltz-recovery Rust kiosk & desktop)
  GET  /health          → {"status":"ok","ai":"mad-dr-boltz","version":"1.1.0",...}
  GET  /sse/events      → Android companion SSE heartbeat & event stream
  GET  /sse/telemetry   → Live hardware & OS telemetry (SSE)
  GET  /sse/commands    → Pending command approvals stream (SSE)
  GET/POST /approve/:token → ntfy.sh approval gate callback
  GET/POST /deny/:token    → Denial gate callback
  POST /api/chat        → MAD AI / Ollama chat relay
  GET  /api/status      → OS status summary
  POST /api/command     → Android command submission
  POST /api/command/decide → Desktop command decision
  GET  /api/token-info  → Local pairing QR info
  POST /api/pairing-code → Node pairing code generation
  POST /api/pair        → Trade pairing code for auth token
"""

import os
import sys
from pathlib import Path

# Locate canonical sse_bridge module
SSE_DIR = Path(__file__).resolve().parent.parent.parent / "mad-dr-ai" / "sse-server"
if str(SSE_DIR) not in sys.path:
    sys.path.insert(0, str(SSE_DIR))

try:
    from sse_bridge import (
        AGENT_MODEL,
        AUTH_TOKEN,
        BUILD_DATE,
        HOST,
        MODEL,
        OLLAMA_URL,
        PORT,
        SYSTEM_PROMPT,
        VERSION,
        app,
        log,
        request_approval,
        stream_ollama,
        verify_auth,
    )
except ImportError:
    # If sse_bridge is in current working directory or PYTHONPATH
    from sse_bridge import (  # type: ignore
        AGENT_MODEL,
        AUTH_TOKEN,
        BUILD_DATE,
        HOST,
        OLLAMA_URL,
        PORT,
        SYSTEM_PROMPT,
        VERSION,
        app,
        log,
        request_approval,
        stream_ollama,
        verify_auth,
    )

EXPOSE = os.getenv("BOLTZ_EXPOSE", "local")
BIND = "127.0.0.1" if EXPOSE == "local" else "0.0.0.0"

if __name__ == "__main__":
    import uvicorn
    listen_port = int(os.getenv("BOLTZ_PORT", os.getenv("SSE_PORT", str(PORT))))
    log.info(f"Mad Dr. Boltz starting unified SSE bridge on :{listen_port} (bind: {BIND})")
    uvicorn.run(app, host=BIND, port=listen_port, log_level="info")
