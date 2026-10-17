"""Tests for the bridge's pairing and token handling. Run: pytest test_pairing.py"""
import importlib
import os
import stat
import sys
import tempfile
from pathlib import Path

import pytest

DATA = tempfile.mkdtemp(prefix="i30ltz-bridge-test-")
os.environ["I30LTZ_DATA_DIR"] = DATA
os.environ.pop("I30LTZ_AUTH_TOKEN", None)
sys.path.insert(0, str(Path(__file__).parent))
bridge = importlib.import_module("sse_bridge")

from fastapi.testclient import TestClient  # noqa: E402

local = TestClient(bridge.app, client=("127.0.0.1", 50000))
remote = TestClient(bridge.app, client=("100.82.1.20", 50000))


@pytest.fixture(autouse=True)
def fresh_pairing_state():
    bridge._pairing.update(code="", expires=0.0, bad=0, locked_until=0.0)


def test_token_file_is_private_and_token_not_logged():
    token_file = Path(DATA) / "config" / "sse_token"
    assert stat.S_IMODE(token_file.stat().st_mode) == 0o600
    token = token_file.read_text().strip()
    assert token == bridge._AUTH_TOKEN
    log_text = (Path(DATA) / "logs" / "sse-bridge.log").read_text()
    assert token not in log_text


def test_token_info_is_local_only():
    r = remote.get("/api/token-info")
    assert r.status_code == 403
    assert bridge._AUTH_TOKEN not in r.text
    r = local.get("/api/token-info")
    assert r.status_code == 200 and r.json()["token"] == bridge._AUTH_TOKEN


def test_proxied_request_is_not_treated_as_local():
    r = local.get("/api/token-info", headers={"X-Forwarded-For": "100.82.1.20"})
    assert r.status_code == 403


def test_pairing_code_only_from_this_machine():
    assert remote.post("/api/pairing-code").status_code == 403
    r = local.post("/api/pairing-code")
    assert r.status_code == 200
    assert len(r.json()["code"]) == 9 and r.json()["code"][4] == "-"


def test_pair_flow_and_single_use():
    code = local.post("/api/pairing-code").json()["code"]
    r = remote.post("/api/pair", json={"code": code.lower().replace("-", " "), "label": "pixel"})
    assert r.status_code == 200
    token = r.json()["token"]
    assert token == bridge._AUTH_TOKEN
    ok = remote.post("/api/command", json={"command": "true"}, headers={"Authorization": f"Bearer {token}"})
    assert ok.status_code == 200
    assert remote.post("/api/pair", json={"code": code}).status_code == 401


def test_unauthenticated_and_wrong_token_rejected():
    assert remote.post("/api/command", json={"command": "true"}).status_code == 401
    r = remote.post("/api/command", json={"command": "true"}, headers={"Authorization": "Bearer nope"})
    assert r.status_code == 401


def test_non_ascii_authorization_header_is_401_not_500():
    r = remote.post("/api/command", json={"command": "true"},
                    headers={"Authorization": "Bearer café".encode("utf-8")})
    assert r.status_code == 401


def test_pair_without_code_fails_and_locks_after_five():
    codes = [remote.post("/api/pair", json={"code": "AAAA-AAAA"}).status_code for _ in range(5)]
    assert codes == [401, 401, 401, 401, 429]
    real = local.post("/api/pairing-code").json()["code"]
    assert remote.post("/api/pair", json={"code": real}).status_code == 429  # locked even for the right code


def test_expired_code_rejected():
    code = local.post("/api/pairing-code").json()["code"]
    bridge._pairing["expires"] = 0.0
    assert remote.post("/api/pair", json={"code": code}).status_code == 401
