#!/usr/bin/env python3
"""
DR. I30LTZ SSE Bridge Server
Version: 1.0.0  |  2026-09-25
Purpose: Android companion app ↔ OS link via Server-Sent Events
Port:    7300

Protocol:
  GET  /sse/telemetry         — live telemetry stream (Android subscribes)
  GET  /sse/ai                — AI response stream (Android subscribes)
  POST /api/command           — send command from Android (requires approval)
  GET  /api/status            — OS status summary
  POST /api/chat              — send message to MAD AI from Android
  WS   /ws/terminal           — optional terminal relay (future)
"""

import asyncio
import hashlib
import json
import logging
import os
import secrets
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import AsyncGenerator, Dict, Optional, Set, Tuple

import httpx
import psutil
from fastapi import BackgroundTasks, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from pydantic import BaseModel
from sse_starlette.sse import EventSourceResponse

# ── Config ────────────────────────────────────────────────────
VERSION = "1.1.0"
BUILD_DATE = "2026-10-14"
PORT = int(os.getenv("SSE_PORT", os.getenv("BOLTZ_PORT", "7300")))
MADIT_URL = os.getenv("MADIT_URL", "http://127.0.0.1:7301")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434")
AGENT_MODEL = os.getenv("AGENT_MODEL", os.getenv("BOLTZ_MODEL", "qwen2.5:7b"))
MODEL = AGENT_MODEL
NTFY_TOPIC = os.getenv("NTFY_TOPIC", "boltz-approval")
AUTH_TOKEN = os.getenv("I30LTZ_AUTH_TOKEN", "") or os.getenv("BOLTZ_AUTH_TOKEN", "") or os.getenv("SWARM_AUTH_TOKEN", "")
# Comma-separated; e.g. "127.0.0.1,100.82.1.19" for this machine + Tailscale. Keep loopback in the list:
# pairing codes and the ntfy approve links only work from this machine.
HOST = os.getenv("SSE_HOST", "127.0.0.1")
# Optional: Dr. Boltz's shared brain (Lucille Assistant's POST /api/chat/i30ltz on Debian: cloud coder model
# first, his own offline model as backup, his rules file). Unset on Recovery OS, which stays offline and
# answers from local Ollama below. If set but unreachable, chat still falls back to local Ollama.
BRAIN_URL = os.getenv("BOLTZ_BRAIN_URL", "")
BRAIN_TOKEN = os.getenv("BOLTZ_BRAIN_TOKEN", "")
BRAIN_TIMEOUT_S = float(os.getenv("BOLTZ_BRAIN_TIMEOUT", "120"))

_default_data_dir = Path(os.getenv("I30LTZ_DATA_DIR", "/opt/i30ltz"))
try:
    _default_data_dir.mkdir(parents=True, exist_ok=True)
    DATA_DIR = _default_data_dir
except (PermissionError, OSError):
    DATA_DIR = Path.home() / ".local" / "share" / "i30ltz"
    DATA_DIR.mkdir(parents=True, exist_ok=True)

LOG_PATH = DATA_DIR / "logs" / "sse-bridge.log"
_log_handlers = [logging.StreamHandler()]
try:
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    _log_handlers.insert(0, logging.FileHandler(LOG_PATH))
except (PermissionError, OSError):
    pass

TOKEN_FILE = DATA_DIR / "config" / "sse_token"
try:
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
except (PermissionError, OSError):
    pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [SSE-BRIDGE] %(levelname)s: %(message)s",
    handlers=_log_handlers
)
log = logging.getLogger("sse_bridge")

# ── Token management ──────────────────────────────────────────
def get_auth_token() -> str:
    if AUTH_TOKEN:
        return AUTH_TOKEN
    if TOKEN_FILE.exists():
        return TOKEN_FILE.read_text().strip()
    # Generate + persist token on first run
    token = secrets.token_urlsafe(32)
    fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)  # never world-readable, even briefly
    with os.fdopen(fd, "w") as fh:
        fh.write(token)
    log.info(f"Generated a new auth token in {TOKEN_FILE} (mode 600). Pair the app with a one-time code: POST /api/pairing-code from this machine.")
    return token

_AUTH_TOKEN = get_auth_token()

def verify_auth(authorization: Optional[str] = None, x_swarm_auth: Optional[str] = None) -> bool:
    # Fail closed: approving a command runs it in a shell, so no token means nobody gets in (RC-23).
    # No public default token is accepted either (INF-10, CP-05).
    if not _AUTH_TOKEN:
        return False
    try:
        if authorization:
            token = authorization.replace("Bearer ", "").strip()
            if secrets.compare_digest(token.encode("utf-8"), _AUTH_TOKEN.encode("utf-8")):
                return True
        if x_swarm_auth:
            token = x_swarm_auth.strip()
            if secrets.compare_digest(token.encode("utf-8"), _AUTH_TOKEN.encode("utf-8")):
                return True
    except Exception:
        return False
    return False

# ── One-time pairing codes ────────────────────────────────────
# The long-lived token is handed out only (a) on the node itself, or (b) in
# exchange for a short code that someone physically at the node generated.
_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # no 0/O/1/I/L
_CODE_TTL_S = 600
_MAX_BAD_CODES = 5
_LOCKOUT_S = 60
_pairing = {"code": "", "expires": 0.0, "bad": 0, "locked_until": 0.0}

def _is_loopback(request: Request) -> bool:
    if request.headers.get("x-forwarded-for") or request.headers.get("forwarded"):
        return False
    host = request.client.host if request.client else ""
    return host in ("127.0.0.1", "::1", "localhost")

def _new_pairing_code() -> str:
    raw = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(8))
    _pairing.update(code=raw, expires=time.monotonic() + _CODE_TTL_S)
    return raw[:4] + "-" + raw[4:]

def _check_pairing_code(given: str) -> str:
    """Returns '' on success, otherwise 'locked' or 'bad'. A code works once."""
    now = time.monotonic()
    if now < _pairing["locked_until"]:
        return "locked"
    given = given.upper().replace("-", "").replace(" ", "").strip()
    ok = bool(_pairing["code"]) and now < _pairing["expires"] and secrets.compare_digest(
        given.encode("utf-8"), _pairing["code"].encode("utf-8"))
    if ok:
        _pairing.update(code="", bad=0)
        return ""
    _pairing["bad"] += 1
    if _pairing["bad"] >= _MAX_BAD_CODES:
        _pairing.update(bad=0, locked_until=now + _LOCKOUT_S)
        return "locked"
    return "bad"

# ── Dr. Boltz System Prompt & Ollama Stream ───────────────────
SYSTEM_PROMPT = """You are Mad Dr. Boltz (DR.BOLTZ), an autonomous AI recovery agent
built on the Lucille cognitive engine. You run on Debian 13 (Trixie) Recovery OS and diagnose/repair failing
operating systems, recover lost data, and fix boot issues.

Rules:
- Always prefix your response with [DR.BOLTZ]
- State confidence level (0-100%) before proposing any fix
- NEVER execute destructive commands (format, wipe, dd, mkfs) — propose them only
- For any destructive action, output: REQUIRES_APPROVAL:<action_id>:<description>
- Be understanding and ready to help at the best of your ability: patient, on the owner's side, calm when things are bad. Plain and honest about problems, no false reassurance, no fluff.
- You have access to: systemd, journalctl, fsck, testdisk, photorec, smartctl, df, lsblk
"""

async def stream_ollama(message: str) -> AsyncGenerator[str, None]:
    """Yields text chunks from Ollama as SSE-ready strings."""
    payload = {
        "model": AGENT_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user",   "content": message},
        ],
        "stream": True,
    }
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            async with client.stream("POST", f"{OLLAMA_URL}/api/chat", json=payload) as resp:
                if resp.status_code != 200:
                    yield f"[DR.BOLTZ] ERROR: Ollama returned HTTP {resp.status_code}"
                    return
                async for raw in resp.aiter_lines():
                    if not raw:
                        continue
                    try:
                        chunk = json.loads(raw)
                        token = chunk.get("message", {}).get("content", "")
                        if token:
                            # Escape newlines so SSE line protocol stays intact
                            yield token.replace("\n", "\\n")
                        if chunk.get("done"):
                            break
                    except json.JSONDecodeError:
                        continue
    except (httpx.ConnectError, httpx.ConnectTimeout):
        yield "[DR.BOLTZ] ERROR: Cannot reach Ollama. Run: ollama serve"
    except Exception as e:
        yield f"[DR.BOLTZ] ERROR: {e}"

def telemetry_brief() -> str:
    """One line of live machine state, so his answers are about this box and not generic."""
    t = collect_telemetry()
    disks = ", ".join(f"{d['mount']} {d['used_pct']:.0f}% used" for d in t["disks"][:6])
    return (f"[Live state of {t['hostname']}: CPU {t['cpu_pct']:.0f}% of {t['cpu_cores']} cores, "
            f"RAM {t['mem_pct']:.0f}% used ({t['mem_avail_gb']} GB free), disks: {disks or 'none read'}, "
            f"up {t['uptime_s'] // 3600} h, {t['pending_commands']} command(s) waiting for approval]")

async def ask_brain(message: str) -> Optional[str]:
    """One full reply from BRAIN_URL, or None so the caller falls back to local Ollama."""
    if not BRAIN_URL:
        return None
    headers = {"X-Swarm-Auth": BRAIN_TOKEN} if BRAIN_TOKEN else {}
    try:
        async with httpx.AsyncClient(timeout=BRAIN_TIMEOUT_S) as client:
            r = await client.post(BRAIN_URL, json={"message": message}, headers=headers)
        j = r.json() if r.headers.get("content-type", "").startswith("application/json") else {}
        text = (j.get("text") or "").strip()
        if r.status_code == 200 and j.get("ok") and text:
            log.info(f"brain replied via {j.get('provider', '?')} {j.get('model', '?')}")
            return text
        log.warning(f"brain gave no reply (HTTP {r.status_code}): {j.get('error', '')[:200]}")
    except Exception as e:
        log.warning(f"brain unreachable, using local Ollama: {e}")
    return None

# ── Pending command queue & approvals ─────────────────────────
_approvals: Dict[str, dict] = {}
_approval_lock = threading.Lock()
_pending_commands: Dict[str, dict] = {}
_approved_commands: Set[str] = set()
_denied_commands: Set[str] = set()

def _post_ntfy_sync(token: str, action: str, description: str):
    if not NTFY_TOPIC:
        return
    try:
        httpx.post(
            f"https://ntfy.sh/{NTFY_TOPIC}",
            content=description.encode(),
            headers={
                "Title": f"[DR.BOLTZ] Approval Required: {action}",
                "Tags": "warning,skull",
                "Priority": "high",
                "Actions": (
                    f"http, Approve, http://localhost:{PORT}/approve/{token},,clear=true; "
                    f"http, Deny, http://localhost:{PORT}/deny/{token},,clear=true"
                ),
            },
            timeout=5.0,
        )
    except Exception as e:
        log.warning(f"ntfy notification failed: {e}")

def request_approval(action: str, description: str) -> Tuple[str, threading.Event]:
    """Push an ntfy.sh notification and return (token, event)."""
    # /approve/{token} takes no other auth (ntfy buttons cannot send headers), so the token itself
    # must be unguessable.
    token = secrets.token_urlsafe(24)
    ev = threading.Event()
    with _approval_lock:
        _approvals[token] = {
            "token": token,
            "action": action,
            "description": description,
            "approved": False,
            "denied": False,
            "event": ev,
            "ts": time.time(),
        }
    if NTFY_TOPIC:
        threading.Thread(
            target=_post_ntfy_sync,
            args=(token, action, description),
            daemon=True
        ).start()
    return token, ev

# ── App ───────────────────────────────────────────────────────
app = FastAPI(
    title="DR. I30LTZ SSE Bridge",
    description="Android ↔ I30LTZ Recovery OS companion bridge",
    version="1.0.0"
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Telemetry collector ───────────────────────────────────────
def collect_telemetry() -> dict:
    try:
        temps = {}
        for k, v in (psutil.sensors_temperatures() or {}).items():
            temps[k] = round(v[0].current, 1) if v else 0
    except Exception:
        temps = {}

    mem = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=0.2)
    disks = []
    for p in psutil.disk_partitions(all=False):
        try:
            u = psutil.disk_usage(p.mountpoint)
            disks.append({
                "dev": p.device,
                "mount": p.mountpoint,
                "used_pct": u.percent,
                "free_gb": round(u.free / 1e9, 1)
            })
        except Exception:
            pass

    return {
        "ts": datetime.now().isoformat(),
        "cpu_pct": cpu,
        "cpu_cores": psutil.cpu_count(),
        "mem_pct": mem.percent,
        "mem_avail_gb": round(mem.available / 1e9, 1),
        "disks": disks,
        "temps": temps,
        "uptime_s": int(time.time() - psutil.boot_time()),
        "hostname": os.uname().nodename,
        "pending_commands": len(_pending_commands),
        "os_version": "I30LTZ Recovery OS 1.0.0"
    }

# ── SSE: Live telemetry stream ────────────────────────────────
@app.get("/sse/telemetry")
async def sse_telemetry(
    request: Request,
    authorization: Optional[str] = Header(None),
    x_swarm_auth: Optional[str] = Header(None, alias="X-Swarm-Auth"),
):
    if not verify_auth(authorization, x_swarm_auth):
        raise HTTPException(status_code=401, detail="Unauthorized")

    async def telemetry_gen() -> AsyncGenerator:
        log.info(f"Client connected: {request.client}")
        try:
            while True:
                if await request.is_disconnected():
                    log.info("Client disconnected")
                    break
                tel = collect_telemetry()
                yield {"event": "telemetry", "data": json.dumps(tel)}
                await asyncio.sleep(2.0)  # 2-second interval
        except asyncio.CancelledError:
            log.info("SSE telemetry stream cancelled")

    return EventSourceResponse(telemetry_gen())

# ── SSE: Command approval stream ──────────────────────────────
@app.get("/sse/commands")
async def sse_commands(
    request: Request,
    authorization: Optional[str] = Header(None),
    x_swarm_auth: Optional[str] = Header(None, alias="X-Swarm-Auth"),
):
    """Android subscribes here to receive pending command approval requests."""
    if not verify_auth(authorization, x_swarm_auth):
        raise HTTPException(status_code=401, detail="Unauthorized")

    async def command_gen() -> AsyncGenerator:
        sent = set()
        while True:
            if await request.is_disconnected():
                break
            # Send new pending commands
            for cmd_id, cmd in list(_pending_commands.items()):
                if cmd_id not in sent:
                    yield {"event": "command_pending", "data": json.dumps(cmd)}
                    sent.add(cmd_id)
            await asyncio.sleep(0.5)

    return EventSourceResponse(command_gen())

# ── SSE: Heartbeat & events stream (boltz_server compat) ───────
@app.get("/sse/events")
async def sse_events(
    request: Request,
    authorization: Optional[str] = Header(None),
    x_swarm_auth: Optional[str] = Header(None, alias="X-Swarm-Auth"),
):
    """Heartbeat & event stream for Android companion app and legacy clients."""
    if not verify_auth(authorization, x_swarm_auth):
        raise HTTPException(status_code=401, detail="Unauthorized")

    async def heartbeat_gen() -> AsyncGenerator:
        while True:
            if await request.is_disconnected():
                break
            yield {"event": "heartbeat", "data": json.dumps({"type": "heartbeat", "ts": int(time.time())})}
            await asyncio.sleep(15.0)

    return EventSourceResponse(heartbeat_gen())

# ── Models ────────────────────────────────────────────────────
class CommandRequest(BaseModel):
    command: str
    description: str = ""
    source: str = "android"  # android|desktop|schedule
    dangerous: bool = False

class CommandDecision(BaseModel):
    cmd_id: str
    approved: bool

class ChatMessage(BaseModel):
    message: str
    include_telemetry: bool = True

# ── Routes ────────────────────────────────────────────────────
@app.get("/health")
async def health():
    """Canonical health check for service monitors, systemd, and kiosks."""
    return {
        "status": "ok",
        "ai": "mad-dr-boltz",
        "version": VERSION,
        "build": BUILD_DATE,
        "model": AGENT_MODEL,
        "ollama": OLLAMA_URL,
        "base_os": "debian",
        "port": PORT,
        "pending_commands": len(_pending_commands),
        "pending_approvals": len(_approvals),
        "token_configured": bool(_AUTH_TOKEN),
    }

@app.get("/api/status")
async def status(
    authorization: Optional[str] = Header(None),
    x_swarm_auth: Optional[str] = Header(None, alias="X-Swarm-Auth"),
):
    if not verify_auth(authorization, x_swarm_auth):
        raise HTTPException(status_code=401, detail="Unauthorized")
    tel = collect_telemetry()
    # Check MAD AI status
    madit_online = False
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            r = await client.get(f"{MADIT_URL}/health")
            madit_online = r.status_code == 200
    except Exception:
        pass

    return {
        **tel,
        "madit_online": madit_online,
        "pending_cmd_count": len(_pending_commands),
        "pending_approval_count": len(_approvals),
        "token_configured": bool(_AUTH_TOKEN),
    }

@app.post("/boltz")
async def boltz(
    req: Request,
    authorization: Optional[str] = Header(None),
    x_swarm_auth: Optional[str] = Header(None, alias="X-Swarm-Auth"),
):
    """Primary chat endpoint for i30ltz-recovery (Raylib kiosk) and desktop UI.
    Streams SSE chunks formatted as data: <chunk>\\n\\n and terminates with data: [DONE]\\n\\n.
    """
    if not verify_auth(authorization, x_swarm_auth):
        raise HTTPException(status_code=401, detail="Unauthorized")

    try:
        data = await req.json()
    except Exception:
        data = {}

    message = (data.get("message") or "").strip()
    if not message:
        raise HTTPException(status_code=400, detail="Empty message")

    async def generate() -> AsyncGenerator[str, None]:
        reply = await ask_brain(message)
        if reply:
            yield f"data: {reply.replace(chr(10), chr(92) + 'n')}\n\n"
        else:
            async for chunk in stream_ollama(message):
                yield f"data: {chunk}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )

@app.post("/api/command")
async def submit_command(
    req: CommandRequest,
    background_tasks: BackgroundTasks,
    authorization: Optional[str] = Header(None),
    x_swarm_auth: Optional[str] = Header(None, alias="X-Swarm-Auth"),
):
    """Android submits a command for user approval."""
    if not verify_auth(authorization, x_swarm_auth):
        raise HTTPException(status_code=401, detail="Unauthorized")

    cmd_id = secrets.token_hex(8)
    cmd_record = {
        "id": cmd_id,
        "command": req.command,
        "description": req.description,
        "source": req.source,
        "dangerous": req.dangerous,
        "submitted_at": datetime.now().isoformat(),
        "status": "pending",
    }
    _pending_commands[cmd_id] = cmd_record
    log.info(f"Command queued [{cmd_id}]: {req.command}")

    return {"cmd_id": cmd_id, "status": "pending"}

@app.post("/api/command/decide")
async def decide_command(
    req: CommandDecision,
    authorization: Optional[str] = Header(None),
    x_swarm_auth: Optional[str] = Header(None, alias="X-Swarm-Auth"),
):
    """Desktop UI approves or denies a pending command."""
    if not verify_auth(authorization, x_swarm_auth):
        raise HTTPException(status_code=401, detail="Unauthorized")

    cmd = _pending_commands.pop(req.cmd_id, None)
    if not cmd:
        raise HTTPException(status_code=404, detail="Command not found or already decided")

    if req.approved:
        _approved_commands.add(req.cmd_id)
        log.info(f"Command APPROVED [{req.cmd_id}]: {cmd['command']}")
        # Execute safely in shell
        try:
            result = subprocess.run(
                cmd["command"], shell=True, capture_output=True,
                text=True, timeout=30
            )
            return {
                "cmd_id": req.cmd_id,
                "status": "executed",
                "returncode": result.returncode,
                "stdout": result.stdout[-2000:],  # cap output
                "stderr": result.stderr[-500:],
            }
        except subprocess.TimeoutExpired:
            return {"cmd_id": req.cmd_id, "status": "timeout"}
        except Exception as e:
            return {"cmd_id": req.cmd_id, "status": "error", "error": str(e)}
    else:
        _denied_commands.add(req.cmd_id)
        log.info(f"Command DENIED [{req.cmd_id}]: {cmd['command']}")
        return {"cmd_id": req.cmd_id, "status": "denied"}

@app.api_route("/approve/{token}", methods=["GET", "POST"])
async def approve(token: str):
    """Approval gate callback for ntfy.sh and companion approvals."""
    with _approval_lock:
        entry = _approvals.get(token)
        if entry:
            entry["approved"] = True
            entry["event"].set()
            log.info(f"Action APPROVED via token [{token}]: {entry.get('action')}")
            return {"status": "approved", "token": token, "action": entry.get("action")}

    # Also check pending commands
    cmd = _pending_commands.pop(token, None)
    if cmd:
        _approved_commands.add(token)
        log.info(f"Command APPROVED via token [{token}]: {cmd['command']}")
        try:
            result = subprocess.run(
                cmd["command"], shell=True, capture_output=True,
                text=True, timeout=30
            )
            return {
                "token": token,
                "status": "executed",
                "command": cmd["command"],
                "returncode": result.returncode,
                "stdout": result.stdout[-2000:],
                "stderr": result.stderr[-500:],
            }
        except subprocess.TimeoutExpired:
            return {"token": token, "status": "timeout", "command": cmd["command"]}
        except Exception as e:
            return {"token": token, "status": "error", "command": cmd["command"], "error": str(e)}

    raise HTTPException(status_code=404, detail="unknown token")

@app.api_route("/deny/{token}", methods=["GET", "POST"])
async def deny(token: str):
    """Denial gate callback for ntfy.sh and companion denials."""
    with _approval_lock:
        entry = _approvals.get(token)
        if entry:
            entry["denied"] = True
            entry["event"].set()
            log.info(f"Action DENIED via token [{token}]: {entry.get('action')}")
            return {"status": "denied", "token": token, "action": entry.get("action")}

    cmd = _pending_commands.pop(token, None)
    if cmd:
        _denied_commands.add(token)
        log.info(f"Command DENIED via token [{token}]: {cmd['command']}")
        return {"token": token, "status": "denied", "command": cmd["command"]}

    raise HTTPException(status_code=404, detail="unknown token")

@app.post("/api/chat")
async def android_chat(
    req: ChatMessage,
    authorization: Optional[str] = Header(None),
    x_swarm_auth: Optional[str] = Header(None, alias="X-Swarm-Auth"),
):
    """Proxy Android chat message to MAD AI or fallback to Ollama, stream SSE back."""
    if not verify_auth(authorization, x_swarm_auth):
        raise HTTPException(status_code=401, detail="Unauthorized")

    async def stream_chat() -> AsyncGenerator:
        # The app reads reply text from "token" (BridgeWire.chatPiece); "text" is silently dropped.
        if BRAIN_URL:
            message = req.message
            if req.include_telemetry:
                try:
                    message = f"{telemetry_brief()}\n\n{req.message}"
                except Exception as e:
                    log.warning(f"telemetry for chat failed: {e}")
            reply = await ask_brain(message)
            if reply:
                yield {"data": json.dumps({"token": reply})}
                yield {"data": json.dumps({"done": True})}
                return

        payload = {
            "message": req.message,
            "include_telemetry": req.include_telemetry,
        }
        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                async with client.stream("POST", f"{MADIT_URL}/api/chat", json=payload) as resp:
                    if resp.status_code == 200:
                        async for line in resp.aiter_lines():
                            if line.startswith("data:"):
                                yield {"data": line[5:].strip()}
                        yield {"data": json.dumps({"done": True})}
                        return
        except Exception:
            pass

        # Fallback directly to Ollama stream
        async for chunk in stream_ollama(req.message):
            yield {"data": json.dumps({"token": chunk.replace("\\n", "\n")})}
        yield {"data": json.dumps({"done": True})}

    return EventSourceResponse(stream_chat())

@app.post("/api/pairing-code")
async def pairing_code(request: Request):
    """Makes a one-time pairing code. Only callable from this machine."""
    if not _is_loopback(request):
        raise HTTPException(status_code=403, detail="Pairing codes can only be created on the node itself")
    return {"code": _new_pairing_code(), "valid_seconds": _CODE_TTL_S}

class PairRequest(BaseModel):
    code: str
    label: str = ""

@app.post("/api/pair")
async def pair(req: PairRequest):
    """Trades a valid one-time code for the bridge token."""
    outcome = _check_pairing_code(req.code)
    if outcome == "locked":
        raise HTTPException(status_code=429, detail="Too many wrong codes; pairing is locked for a minute",
                            headers={"Retry-After": str(_LOCKOUT_S)})
    if outcome == "bad":
        raise HTTPException(status_code=401, detail="Pairing code is wrong or expired")
    log.info(f"Device paired: {req.label[:64] or 'unnamed'}")
    return {"token": _AUTH_TOKEN, "hostname": os.uname().nodename}

@app.get("/api/token-info")
async def token_info(request: Request):
    """Pairing info for the QR code shown on the node's own screen. Local requests only:
    this response contains the token, so it must never be served over the network."""
    if not _is_loopback(request):
        raise HTTPException(status_code=403, detail="token-info is only available on the node itself")
    import socket
    hostname = socket.gethostname()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = "127.0.0.1"

    return {
        "server_url": f"http://{local_ip}:{PORT}",
        "token": _AUTH_TOKEN,
        "qr_payload": json.dumps({
            "type": "i30ltz_pair",
            "url": f"http://{local_ip}:{PORT}",
            "token": _AUTH_TOKEN
        })
    }

@app.get("/", response_class=HTMLResponse)
async def root():
    return f"""<!DOCTYPE html>
<html><head><meta charset='utf-8'>
<title>DR. I30LTZ SSE Bridge</title>
<style>
body{{background:#08080c;color:#e0e0e4;font-family:monospace;padding:2rem}}
h1{{color:#ba0c2f}} code{{color:#00c850}}
</style></head><body>
<h1>DR. I30LTZ SSE Bridge v{VERSION}</h1>
<p>I30LTZ Recovery OS  |  {BUILD_DATE}</p>
<hr>
<p><code>GET  /health</code> — service health &amp; AI status</p>
<p><code>POST /boltz</code> — SSE chat stream (Rust kiosk &amp; desktop shell)</p>
<p><code>GET  /sse/telemetry</code> — live system telemetry (SSE)</p>
<p><code>GET  /sse/commands</code> — pending command approvals (SSE)</p>
<p><code>GET  /sse/events</code> — heartbeat &amp; event stream (SSE)</p>
<p><code>POST /api/chat</code> — relay to MAD AI / Ollama</p>
<p><code>GET  /api/status</code> — OS status JSON</p>
<p><code>POST /api/command</code> — submit command for approval</p>
<p><code>POST /api/command/decide</code> — approve/deny command</p>
<p><code>GET/POST /approve/:token</code> — approval gate callback</p>
<p><code>GET/POST /deny/:token</code> — denial gate callback</p>
<p><code>GET  /api/token-info</code> — pairing QR info (this machine only)</p>
<p><code>POST /api/pairing-code</code> — one-time pairing code (this machine only)</p>
<p><code>POST /api/pair</code> — trade a pairing code for the token</p>
</body></html>"""

if __name__ == "__main__":
    import socket
    import uvicorn
    hosts = [h.strip() for h in HOST.split(",") if h.strip()]
    log.info(f"DR. I30LTZ SSE Bridge v{VERSION} starting on {', '.join(hosts)} :{PORT}"
             f" (brain: {BRAIN_URL or 'local Ollama only'})")
    if len(hosts) == 1:
        uvicorn.run(app, host=hosts[0], port=PORT, log_level="info")
    else:
        # uvicorn binds one host; several addresses (loopback + Tailscale) need pre-bound sockets.
        socks = []
        for h in hosts:
            s = socket.socket(socket.AF_INET6 if ":" in h else socket.AF_INET, socket.SOCK_STREAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((h, PORT))
            socks.append(s)
        uvicorn.Server(uvicorn.Config(app, log_level="info")).run(sockets=socks)
