"""RC-23: auth fails closed, no public default token, unguessable approval tokens, and the optional shared brain.
Run on its own (each test file imports sse_bridge once with its own data dir): pytest test_rc23.py
"""
import importlib
import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, patch

DATA = tempfile.mkdtemp(prefix="i30ltz-rc23-test-")
os.environ["I30LTZ_DATA_DIR"] = DATA
os.environ.pop("I30LTZ_AUTH_TOKEN", None)
sys.path.insert(0, str(Path(__file__).parent))
bridge = importlib.import_module("sse_bridge")

import pytest
from fastapi.testclient import TestClient
from sse_starlette.sse import AppStatus

client = TestClient(bridge.app, client=("127.0.0.1", 50000))


@pytest.fixture(autouse=True)
def _fresh_sse_exit_event():
    # sse_starlette keeps one exit Event bound to the first test's event loop; each TestClient call has its own.
    AppStatus.should_exit_event = None
    yield
token = bridge._AUTH_TOKEN
auth = {"Authorization": f"Bearer {token}"}


def sse_payloads(text: str) -> list:
    return [line[5:].strip() for line in text.splitlines() if line.startswith("data:")]


def test_public_default_token_is_rejected():
    assert not bridge.verify_auth(None, "swarm-token-2026")
    r = client.post("/api/command", json={"command": "id"}, headers={"X-Swarm-Auth": "swarm-token-2026"})
    assert r.status_code == 401


def test_no_token_configured_fails_closed():
    with patch.object(bridge, "_AUTH_TOKEN", ""):
        assert not bridge.verify_auth(None, None)
        assert not bridge.verify_auth("Bearer ", "")
        assert client.get("/api/status").status_code == 401


def test_real_token_still_works_both_headers():
    assert bridge.verify_auth(f"Bearer {token}", None)
    assert bridge.verify_auth(None, token)


def test_approval_token_is_unguessable():
    t, _ = bridge.request_approval("test", "rc23")
    assert len(t) >= 32
    bridge._approvals.pop(t, None)


def test_default_host_is_loopback():
    assert bridge.HOST == os.getenv("SSE_HOST", "127.0.0.1")
    if "SSE_HOST" not in os.environ:
        assert bridge.HOST == "127.0.0.1"


def test_ask_brain_is_off_without_url():
    import asyncio
    with patch.object(bridge, "BRAIN_URL", ""):
        assert asyncio.run(bridge.ask_brain("hi")) is None


def test_chat_uses_brain_and_app_readable_key():
    brain = AsyncMock(return_value="Disk is 91% full.\nClear the journal.")
    with patch.object(bridge, "BRAIN_URL", "http://brain.invalid/api/chat/i30ltz"), \
         patch.object(bridge, "ask_brain", brain):
        r = client.post("/api/chat", json={"message": "why is it slow", "include_telemetry": True}, headers=auth)
    assert r.status_code == 200
    payloads = [json.loads(p) for p in sse_payloads(r.text)]
    assert payloads[0] == {"token": "Disk is 91% full.\nClear the journal."}
    assert payloads[-1] == {"done": True}
    sent = brain.await_args.args[0]
    assert sent.startswith("[Live state of ") and sent.endswith("why is it slow")


def test_chat_without_telemetry_sends_message_as_is():
    brain = AsyncMock(return_value="ok")
    with patch.object(bridge, "BRAIN_URL", "http://brain.invalid/api/chat/i30ltz"), \
         patch.object(bridge, "ask_brain", brain):
        client.post("/api/chat", json={"message": "hello", "include_telemetry": False}, headers=auth)
    assert brain.await_args.args[0] == "hello"


async def _fake_ollama(_message):
    yield "Local "
    yield "answer"


def test_chat_falls_back_to_ollama_with_token_key():
    with patch.object(bridge, "BRAIN_URL", "http://brain.invalid/api/chat/i30ltz"), \
         patch.object(bridge, "ask_brain", AsyncMock(return_value=None)), \
         patch.object(bridge, "MADIT_URL", "http://127.0.0.1:9"), \
         patch.object(bridge, "stream_ollama", _fake_ollama):
        r = client.post("/api/chat", json={"message": "x", "include_telemetry": False}, headers=auth)
    payloads = [json.loads(p) for p in sse_payloads(r.text)]
    assert {"token": "Local "} in payloads and {"token": "answer"} in payloads
    assert all("text" not in p for p in payloads)
    assert payloads[-1] == {"done": True}


def test_boltz_endpoint_uses_brain_with_escaped_newlines():
    with patch.object(bridge, "ask_brain", AsyncMock(return_value="line one\nline two")):
        r = client.post("/boltz", json={"message": "status"}, headers=auth)
    assert sse_payloads(r.text) == ["line one\\nline two", "[DONE]"]
