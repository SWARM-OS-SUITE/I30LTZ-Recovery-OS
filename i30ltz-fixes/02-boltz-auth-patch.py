#!/usr/bin/env python3
"""
FIX C4 + H1 — Harden boltz_server.py
  · Add X-Swarm-Auth token validation on POST /boltz  (H1)
  · Add SSE heartbeat keepalive with reconnect-friendly headers (Medium)
  · Ensure SWARM_AUTH_TOKEN env var is required at startup (C4 partial)
I30LTZ Recovery OS · 2026-10-06
Run: python3 02-boltz-auth-patch.py /mnt/recoverybuild/30-source/mad-dr-boltz/brain/boltz_server.py
"""
import sys, re, shutil, os
from datetime import datetime

FIX_TAG = "# [FIX-2026-10-06]"

# ── Auth middleware block to inject ──────────────────────────────────────────
AUTH_BLOCK = '''
{tag} Auth middleware — X-Swarm-Auth token validation
import hmac as _hmac, os as _os
_SWARM_TOKEN = _os.environ.get("SWARM_AUTH_TOKEN", "")
if not _SWARM_TOKEN or len(_SWARM_TOKEN) < 16:
    raise RuntimeError(
        "SWARM_AUTH_TOKEN is unset or too short (<16 chars). "
        "Set it in /mnt/recoverybuild/80-vm/.env before starting boltz_server.py"
    )

def _require_auth():
    """Call at the top of any sensitive route handler."""
    hdr = request.headers.get("X-Swarm-Auth", "")
    if not _hmac.compare_digest(hdr.encode(), _SWARM_TOKEN.encode()):
        from flask import abort
        abort(401, description="Invalid or missing X-Swarm-Auth token")

'''.format(tag=FIX_TAG)

# ── SSE headers upgrade ───────────────────────────────────────────────────────
SSE_CACHE_HEADERS = (
    "    response.headers['Cache-Control'] = 'no-cache'\\n"
    "    response.headers['X-Accel-Buffering'] = 'no'\\n"
    "    response.headers['Connection'] = 'keep-alive'\\n"
    "{tag} SSE headers ensure Android companion can reconnect cleanly\\n".format(tag=FIX_TAG)
)

# ── Heartbeat generator ───────────────────────────────────────────────────────
HEARTBEAT_SNIPPET = """
{tag} SSE heartbeat — keeps the connection alive and lets Android detect drops
def _sse_heartbeat(gen, interval=15):
    import time, threading
    last = [time.time()]
    def _ticker():
        while True:
            time.sleep(interval)
            last[0] = 0  # signal heartbeat needed
    t = threading.Thread(target=_ticker, daemon=True)
    t.start()
    for chunk in gen:
        if last[0] == 0:
            yield "data: {{\\\"type\\\": \\\"heartbeat\\\", \\\"ts\\\": " + str(int(time.time())) + "}}\\n\\n"
            last[0] = time.time()
        yield chunk

""".format(tag=FIX_TAG)


def patch(path: str):
    if not os.path.isfile(path):
        print(f"ERROR: {path} not found")
        sys.exit(1)

    original = open(path, "r", encoding="utf-8").read()

    if FIX_TAG in original:
        print(f"SKIP: {path} already patched (found {FIX_TAG})")
        return

    # Backup
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = f"{path}.bak-{ts}"
    shutil.copy2(path, backup)
    print(f"  Backup: {backup}")

    patched = original

    # 1. Find Flask app creation and inject auth block after it
    app_init = re.search(r"^(app\s*=\s*Flask\([^)]*\))", patched, re.MULTILINE)
    if app_init:
        insert_pos = app_init.end()
        patched = patched[:insert_pos] + "\n" + AUTH_BLOCK + patched[insert_pos:]
        print("  [+] Injected X-Swarm-Auth middleware after Flask() init")
    else:
        print("  [!] Could not locate app = Flask(...) — auth block not injected")
        print("      Add this manually after your Flask app is created:")
        print(AUTH_BLOCK)

    # 2. Add _require_auth() call inside the /boltz route
    boltz_route = re.search(
        r"(@app\.route\(['\"/boltz][^)]*\)[^)]*\)\s*\ndef\s+\w+\([^)]*\):)",
        patched, re.MULTILINE
    )
    if boltz_route:
        # Find the first line of the function body and insert _require_auth()
        body_start = boltz_route.end()
        # Insert after the def line — find next newline then add call
        nl = patched.find("\n", body_start)
        indent = "    "  # assume 4-space indent
        call_line = f"\n{indent}_require_auth()  {FIX_TAG} validate X-Swarm-Auth\n"
        patched = patched[:nl] + call_line + patched[nl:]
        print("  [+] Injected _require_auth() into /boltz route")
    else:
        print("  [!] Could not auto-locate /boltz route body — add manually:")
        print("      _require_auth()  # at the very first line of the /boltz handler")

    # 3. Inject heartbeat helper before any /sse route
    sse_route = re.search(
        r"@app\.route\(['\"].*sse.*['\"]",
        patched, re.MULTILINE | re.IGNORECASE
    )
    if sse_route:
        insert_pos = sse_route.start()
        patched = patched[:insert_pos] + HEARTBEAT_SNIPPET + patched[insert_pos:]
        print("  [+] Injected _sse_heartbeat() helper before SSE route")
    else:
        print("  [!] No /sse route found — skipping heartbeat injection")

    with open(path, "w", encoding="utf-8") as f:
        f.write(patched)

    print(f"\n  DONE: {path} patched successfully")
    print("  Required env: SWARM_AUTH_TOKEN=<your-token> (min 16 chars)")
    print("  Restart: systemctl restart boltz 2>/dev/null || python3 boltz_server.py")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        default = "/mnt/recoverybuild/30-source/mad-dr-boltz/brain/boltz_server.py"
        print(f"Usage: python3 {sys.argv[0]} <path-to-boltz_server.py>")
        print(f"Default path: {default}")
        sys.exit(1)
    print(f"==> [H1+C4] Patching {sys.argv[1]} ...")
    patch(sys.argv[1])
