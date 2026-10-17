"""Tests for the merged Dr. Boltz endpoints: /health, /boltz, /sse/events, /approve, /deny, and X-Swarm-Auth.
Run: pytest test_boltz_endpoints.py
"""
import importlib
import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest

DATA = tempfile.mkdtemp(prefix="i30ltz-boltz-test-")
os.environ["I30LTZ_DATA_DIR"] = DATA
os.environ.pop("I30LTZ_AUTH_TOKEN", None)
sys.path.insert(0, str(Path(__file__).parent))
bridge = importlib.import_module("sse_bridge")

from fastapi.testclient import TestClient

client = TestClient(bridge.app, client=("127.0.0.1", 50000))
token = bridge._AUTH_TOKEN


def test_health_endpoint():
    r = client.get("/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert data["ai"] == "mad-dr-boltz"
    assert "version" in data
    assert "model" in data
    assert "ollama" in data
    assert data["base_os"] == "debian"


def test_boltz_unauthorized():
    r = client.post("/boltz", json={"message": "hello"})
    assert r.status_code == 401


def test_boltz_empty_message():
    r = client.post("/boltz", json={"message": ""}, headers={"X-Swarm-Auth": token})
    assert r.status_code == 400


def test_boltz_with_x_swarm_auth_and_bearer():
    # Test with X-Swarm-Auth
    with patch("sse_bridge.stream_ollama") as mock_stream:
        async def fake_stream(msg):
            yield "[DR.BOLTZ] System diagnosis: all normal."

        mock_stream.side_effect = fake_stream
        r = client.post("/boltz", json={"message": "check disk"}, headers={"X-Swarm-Auth": token})
        assert r.status_code == 200
        assert "text/event-stream" in r.headers["content-type"]
        assert "data: [DR.BOLTZ] System diagnosis: all normal.\n\ndata: [DONE]\n\n" in r.text

    # Test with Bearer auth
    with patch("sse_bridge.stream_ollama") as mock_stream:
        async def fake_stream(msg):
            yield "Second chunk."

        mock_stream.side_effect = fake_stream
        r = client.post("/boltz", json={"message": "check disk"}, headers={"Authorization": f"Bearer {token}"})
        assert r.status_code == 200
        assert "data: Second chunk.\n\ndata: [DONE]\n\n" in r.text


def test_approve_and_deny_approval_gate():
    tok, ev = bridge.request_approval("repair_grub", "Reinstall GRUB to /dev/sda")
    assert tok in bridge._approvals
    assert not ev.is_set()

    # GET /approve/:token
    r = client.get(f"/approve/{tok}")
    assert r.status_code == 200
    assert r.json()["status"] == "approved"
    assert r.json()["action"] == "repair_grub"
    assert ev.is_set()

    # Deny on another token
    tok2, ev2 = bridge.request_approval("wipe_disk", "Wipe partition sdb1")
    r2 = client.post(f"/deny/{tok2}")
    assert r2.status_code == 200
    assert r2.json()["status"] == "denied"
    assert ev2.is_set()

    # Unknown token
    r_bad = client.get("/approve/invalidtoken123")
    assert r_bad.status_code == 404


def test_approve_pending_command():
    cmd_res = client.post(
        "/api/command",
        json={"command": "echo test_approve_cmd"},
        headers={"X-Swarm-Auth": token}
    )
    assert cmd_res.status_code == 200
    cmd_id = cmd_res.json()["cmd_id"]

    # Approve via /approve/:token callback
    r = client.post(f"/approve/{cmd_id}")
    assert r.status_code == 200
    assert r.json()["status"] == "executed"
    assert "test_approve_cmd" in r.json()["stdout"]


def test_deny_pending_command():
    cmd_res = client.post(
        "/api/command",
        json={"command": "echo denied"},
        headers={"Authorization": f"Bearer {token}"}
    )
    assert cmd_res.status_code == 200
    cmd_id = cmd_res.json()["cmd_id"]

    # Deny via /deny/:token
    r = client.get(f"/deny/{cmd_id}")
    assert r.status_code == 200
    assert r.json()["status"] == "denied"


def test_sse_events_auth():
    # Unauthorized
    assert client.get("/sse/events").status_code == 401
    assert client.get("/sse/events", headers={"X-Swarm-Auth": "wrong"}).status_code == 401
    assert client.get("/sse/events", headers={"Authorization": "Bearer wrong"}).status_code == 401
