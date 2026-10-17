# shellcheck shell=bash
# about: coding, gaming and ISO build/test tools for developing both OSes
# SWARM_OS Suite dev workstation v2.0.0 · 2026-09-30

# ── Coding ─────────────────────────────────────────────────────────────────
apt_install git git-lfs build-essential pkg-config cmake clang lld \
  libssl-dev python3 python3-venv python3-pip curl ca-certificates \
  jq ripgrep fd-find tmux htop btop shellcheck
apt_optional rustup
if have rustup || [[ "$DRY_RUN" == 1 ]]; then
  run sudo -u "$TARGET_USER" -H rustup default stable \
    || warn "rustup could not fetch stable — run later:  rustup default stable"
fi

# ── Build + boot-test both OS images without touching this machine ─────────
#   SWARM_OS is Arch-based (archiso): arch-install-scripts gives pacstrap.
#   I30LTZ Recovery OS is Ubuntu-based: debootstrap + live-build.
#   QEMU + OVMF boot either ISO in a window (UEFI + Secure Boot capable).
apt_install qemu-system-x86 qemu-utils ovmf xorriso squashfs-tools mtools
apt_optional arch-install-scripts debootstrap live-build virt-manager
if getent group kvm >/dev/null; then run usermod -aG kvm "$TARGET_USER"; fi

# ── Gaming (this is also your daily machine) ───────────────────────────────
apt_optional gamemode mangohud
if getent group gamemode >/dev/null; then run usermod -aG gamemode "$TARGET_USER"; fi
# Steam asks you to accept Valve's license — that's your call, so it's not
# auto-accepted here. One command when you're ready:
pkg_installed steam-installer || warn "Steam not installed — when ready:  sudo apt install steam-installer"

# ── Shared dev area (NOT an OS install — never named swarm_os or i30ltz) ───
getent group suitedev >/dev/null || run groupadd --system suitedev
run usermod -aG suitedev "$TARGET_USER"
for d in /opt/suite-dev /opt/suite-dev/models /opt/suite-dev/iso-test /etc/suite-dev; do
  run install -d -o root -g suitedev -m 2775 "$d"
done
run chmod 0755 /etc/suite-dev

write_file /etc/suite-dev/release 0644 <<'CFG'
# SWARM_OS Suite — dev workstation identity (this machine is neither OS)
ROLE="dev-workstation"
BUILDS="SWARM_OS (Arch, internal), I30LTZ Recovery OS (Ubuntu, external)"
FIRST_BOOT_KIT="2.0.0"
FIRST_BOOT_DATE="2026-09-30"
CFG
ok "dev workstation ready: /opt/suite-dev (models, iso-test)"
