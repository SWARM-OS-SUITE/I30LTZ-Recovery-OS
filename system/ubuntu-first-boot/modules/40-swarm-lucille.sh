# shellcheck shell=bash
# about: SWARM_OS · LUCILLE CORE AI "LLcy" — coding + gaming + AI workspace
# SWARM_OS Suite · Ubuntu First Boot v1.0.0 · 2026-09-30

if ! wants swarm; then info "profile=$PROFILE — SWARM_OS part skipped"; return 0; fi

# ── Coding ─────────────────────────────────────────────────────────────────
apt_install git git-lfs build-essential pkg-config cmake clang lld \
  libssl-dev python3 python3-venv python3-pip curl ca-certificates \
  jq ripgrep fd-find tmux htop btop shellcheck
apt_optional rustup
if have rustup || [[ "$DRY_RUN" == 1 ]]; then
  run sudo -u "$TARGET_USER" -H rustup default stable \
    || warn "rustup could not fetch stable — run later:  rustup default stable"
fi

# ── Gaming ─────────────────────────────────────────────────────────────────
apt_optional gamemode mangohud steam-installer
if getent group gamemode >/dev/null; then run usermod -aG gamemode "$TARGET_USER"; fi

# ── LLcy home: /opt/swarm_os (matches the SWARM OS layout) ─────────────────
getent group swarm >/dev/null || run groupadd --system swarm
run usermod -aG swarm "$TARGET_USER"
for d in /opt/swarm_os /opt/swarm_os/bin /opt/swarm_os/lucille /opt/swarm_os/lucille/models \
         /etc/swarm_os /var/lib/swarm_os /var/log/swarm_os; do
  run install -d -o root -g swarm -m 2775 "$d"
done
run chmod 0755 /etc/swarm_os

write_file /etc/swarm_os/release 0644 <<'CFG'
# SWARM_OS Suite — machine identity
SUITE="SWARM_OS"
ASSISTANT="LUCILLE CORE AI (LLcy)"
FIRST_BOOT_KIT="1.0.0"
FIRST_BOOT_DATE="2026-09-30"
BASE="Ubuntu LTS"
CFG

write_file /etc/swarm_os/lucille.toml 0644 <<'CFG'
# LUCILLE CORE AI "LLcy" — local assistant config
# v0.1.0 | 2026-09-30
# Local-first: models live on this PC; nothing listens on the network.
listen      = "127.0.0.1:5000"   # loopback only — firewall blocks outside anyway
models_dir  = "/opt/swarm_os/lucille/models"
data_dir    = "/var/lib/swarm_os"
roles       = ["daily-life", "gaming", "coding"]

[gpu]
# Integrated graphics: offload a few layers via Vulkan, rest on CPU.
backend    = "vulkan"
gpu_layers = 8
CFG
ok "LLcy workspace ready: /opt/swarm_os  (group: swarm)"
