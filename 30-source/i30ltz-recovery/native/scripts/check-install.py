#!/usr/bin/env python3
"""Install/uninstall inside an isolated target directory, never the real OS."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
(root / "target").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="install-check-", dir=root / "target") as temp:
    stage = Path(temp)
    command = ["make", "-C", str(root), "install", "DESTDIR=" + temp]
    subprocess.run(command, check=True)
    prefix = stage / "opt/i30ltz"
    launcher = stage / "usr/local/bin/i30ltz"
    env = dict(os.environ, I30LTZ_PREFIX=str(prefix))
    env.pop("I30LTZ_CONFIG", None)
    for flag in ("--version", "--check-config"):
        subprocess.run([str(launcher), flag], env=env, check=True)
    # Installing again must not replace the user's existing configuration.
    config = prefix / "config/i30ltz.toml"
    config.write_text(config.read_text() + "\n# Preserve this user customization.\n")
    expected = config.read_bytes()
    subprocess.run(command, check=True)
    assert config.read_bytes() == expected
    subprocess.run(["make", "-C", str(root), "uninstall", "DESTDIR=" + temp], check=True)
    assert config.read_bytes() == expected
    assert not launcher.exists()
    assert not any((prefix / "bin").iterdir())
print("Staged install, launcher, config preservation and uninstall checks passed.")
