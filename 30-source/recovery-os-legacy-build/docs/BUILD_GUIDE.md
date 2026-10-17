# I30LTZ Recovery OS — Build Guide
**Version:** 1.0.0 (NIGHTFALL)  |  **Date:** 2026-09-25  
**AI:** DR. I30LTZ "MAD IT"  |  **Base:** Ubuntu 24.04 LTS + XFCE4

---

## Requirements

### Build machine (Ubuntu/Debian)
```bash
sudo apt install -y \
  debootstrap squashfs-tools genisoimage \
  xorriso mtools syslinux-utils \
  grub-pc-bin grub-efi-amd64-bin
```

### Hardware target
- x86_64 CPU (integrated graphics OK — iGPU supported)
- 2GB RAM minimum (4GB recommended for AI)
- 8GB USB stick for live ISO
- 20GB+ disk for install

---

## Build Steps

```bash
cd /mnt/recoverybuild/I30LTZ_Recovery_OS

# Full build (stages 1-6)
sudo ./build.sh all

# Or stage by stage:
sudo ./build.sh 1   # debootstrap
sudo ./build.sh 2   # chroot customization
sudo ./build.sh 3   # squashfs
sudo ./build.sh 4   # kernel
sudo ./build.sh 5   # grub
sudo ./build.sh 6   # ISO
```

Output: `releases/i30ltz-recovery-os_1.0.0_<date>_amd64.iso`

---

## Flash to USB

```bash
# Identify USB: lsblk
sudo dd if=releases/i30ltz-recovery-os_1.0.0_*.iso \
         of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## Boot Modes

| Menu Entry | Use Case |
|---|---|
| **Live Session** | Default — boots XFCE, DR. I30LTZ launches |
| **Safe Mode** | iGPU issues / display problems |
| **RAM Mode** | Full ISO loaded to RAM (fast, read-only USB) |
| **Check Disk** | Verify ISO integrity |
| **Install** | Install to NVMe/SSD |

---

## Services (Live + Installed)

| Service | Port | Purpose |
|---|---|---|
| `ollama` | 11434 | Local LLM inference |
| `madit` | 7301 | DR. I30LTZ AI inference API |
| `i30ltz-sse` | 7300 | Android companion SSE bridge |
| `i30ltz-watchdog` | — | Auto-restarts crashed services |

```bash
# Check status
systemctl status madit i30ltz-sse ollama

# AI chat test
curl http://localhost:7301/api/version

# Telemetry
curl http://localhost:7301/api/telemetry

# Android pairing
/opt/i30ltz/scripts/show-pair-qr.sh
```

---

## Android Companion Connection

1. Boot I30LTZ Recovery OS
2. Run: `/opt/i30ltz/scripts/show-pair-qr.sh`
3. Scan QR code with I30LTZ Android app
4. Android connects to SSE bridge on port 7300
5. Live telemetry streams to phone automatically

**SSE endpoints:**
- `GET /sse/telemetry` — live system stats (2s interval)
- `GET /sse/commands` — pending command approvals
- `POST /api/chat` — relay to DR. I30LTZ MAD IT
- `POST /api/command` — submit command for approval

---

## DR. I30LTZ App (Rust + Raylib)

The existing `i30ltz-recovery` binary (v0.1.0) is the primary UI.

```bash
# Sync binary from boltz drive
sudo /mnt/Lucy/70-scripts/sync_lucille_ai.sh

# Or build from source
cd /mnt/Lucy/30-source/i30ltz-recovery
cargo build --release
sudo cp target/release/i30ltz-recovery /opt/i30ltz/bin/

# Run manually
LUCY_URL=http://127.0.0.1:7301 \
SWARM_AUTH_TOKEN=i30ltz-2026 \
/opt/i30ltz/bin/i30ltz-recovery
```

---

## Folder Layout

```
I30LTZ_Recovery_OS/
├── build.sh                 ← Master build script
├── chroot/                  ← Chroot customization (runs in order)
│   ├── 00-base.sh           — locale, APT, users, security
│   ├── 10-desktop.sh        — XFCE4, LightDM, fonts
│   ├── 20-recovery-tools.sh — testdisk, ddrescue, gparted, etc.
│   ├── 30-ai-setup.sh       — Ollama + MAD IT Python API
│   ├── 40-sse-bridge.sh     — Android SSE bridge service
│   ├── 50-dr-i30ltz-app.sh  — Recovery GUI binary + autostart
│   └── 60-finalize.sh       — initramfs, cleanup, manifest
├── config/
│   ├── grub/grub.cfg        — GRUB boot menu
│   ├── systemd/             — systemd unit files
│   └── xfce4/               — desktop config
├── sse-server/
│   └── sse_bridge.py        — Android SSE bridge server
├── scripts/
│   ├── install-to-disk.sh   — TUI disk installer
│   ├── watchdog.sh          — service watchdog
│   └── (others)
├── iso/                     ← Built ISO structure
│   ├── boot/grub/
│   ├── casper/
│   └── live/
├── releases/                ← Final ISOs
└── docs/
    └── BUILD_GUIDE.md       ← This file
```

---

## Version History

| Version | Date | Notes |
|---|---|---|
| 1.0.0 | 2026-09-25 | Initial build — Ubuntu 24.04 + XFCE4 + MAD IT + SSE |
