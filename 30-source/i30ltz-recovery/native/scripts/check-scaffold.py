#!/usr/bin/env python3
"""Smoke-test scaffold binaries only; never launches GUIs or opens devices."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
env = dict(os.environ, I30LTZ_CONFIG=str(root / "config/i30ltz.toml"))
for name in ("i30ltz-shell", "mad-it", "i30cm", "i30ltz-hwdash", "drivescan", "reportgen"):
    binary = root / "target/debug" / name
    for args, expected in [(["--version"], 0), (["--help"], 0), (["--check-config"], 0), ([], 2), (["--not-a-command"], 2)]:
        result = subprocess.run([str(binary), *args], env=env, capture_output=True, text=True, timeout=10)
        assert result.returncode == expected, (name, args, result.stderr)
    missing = dict(env, I30LTZ_CONFIG=str(root / "does-not-exist.toml"))
    result = subprocess.run([str(binary), "--check-config"], env=missing, capture_output=True, timeout=10)
    assert result.returncode == 1, name
    with tempfile.TemporaryDirectory() as temp:
        config_dir = Path(temp) / "i30ltz"
        config_dir.mkdir()
        (config_dir / "i30ltz.toml").write_text("invalid = [")
        user_env = dict(env, XDG_CONFIG_HOME=temp)
        user_env.pop("I30LTZ_CONFIG")
        result = subprocess.run([str(binary), "--check-config"], env=user_env, capture_output=True, timeout=10)
        assert result.returncode == 1, name
print("42 CLI checks passed across all six scaffold binaries.")
