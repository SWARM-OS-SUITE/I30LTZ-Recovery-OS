# I30LTZ RECOVERY OS — Codex Context
**Version:** 0.1.0-alpha | **Date:** 2026-10-05

## READ FIRST (all AIs, all 4 projects)
`00-CURRENT/AI_INSTRUCTIONS.md` (rules + start-of-session steps) · `00-CURRENT/MASTER_BUILD_LIST.md` (all open work, prioritized)
· `00-CURRENT/MOUNTS.md` (canonical mounts) · `bash 70-scripts/ai-board.sh list` (who is working where; claim before editing).

## Project Identity
- **OS Name:** I30LTZ Recovery OS (codename: **MAD AI**, written "I30LTZ MAD AI")
  - **Never write "MAD IT".** The user fixed this on 2026-10-10: "AI" vs "IT" is a big difference. Old docs, code and the
    phone app may still say MAD IT: fix it where you touch it. Lower-case code identifiers (`apps/mad-it`, `mad-it.gguf`,
    `50-recovery-mad-it.sh`, `madit_online`) are not renamed yet: tracked as RC-21.
- **AI:** Dr. I30LTZ ("THE MAD DR.") — local Ollama, 7B max
- **AI memory:** Dr. I30LTZ's **standalone memory is kept inside the OS** (installed root on `/mnt/recoveryos`). Never on a
  build partition, in the ISO, in git or in the cloud. The exact path/layout is RC-20 (decision pending).
- **Base:** Debian (live-build)
- **Build Root:** /mnt/recoverybuild
- **Build Output:** `/mnt/ventoy/ISO/recovery-os/` keeps the newest 5; `/mnt/recoverybuild/10-releases/` keeps only the newest 1 (aborts if Ventoy UUID 5ABB-83DF not mounted at /mnt/ventoy)
- **Installed Root:** /mnt/recoveryos
- **Install drive (user, 2026-10-10):** the Samsung T7, cleaned and laid out as **1 GB EFI** (`2D87-5490`) + **~453 GB
  btrfs "Recovery OS"** (`96969ed2-…`) + 5.9 GB swap + **~472 GB deliberately left free** for a possible future OS
  (last partition, unformatted, GPT name "FREE reserved for a future OS"). The disk is **GPT** (redone from a mistaken MBR the same day). Leave the free partition alone. Details: `00-CURRENT/MOUNTS.md`. Disk letters
  change between boots (it was `sdb`), so always target by UUID.

## Hardware Constraints
- Integrated graphics only (no dGPU)
- 7B parameter max for local LLM
- Must boot and repair with ZERO external drives required

## Key Paths
| Purpose | Path |
|---------|------|
| ISO profile | /mnt/recoverybuild/40-iso-profile/ |
| AI backend | /mnt/recoverybuild/30-source/mad-dr-ai/ |
| Enterprise app | /mnt/recoverybuild/30-source/enterprise-app/ |
| Android companion (I30LTZ Companion = the Boltz Recovery phone app, build partition D) | /mnt/boltzbuild/src/I30LTZ-Recovery-companion/ (moved 2026-10-09) |
| Node agent (runs on each machine) | /mnt/recoverybuild/30-source/i30ltz-node/ |
| Build scripts | /mnt/recoverybuild/70-scripts/ |
| AI brain/agents | /mnt/recoverybuild/60-brain/ |

## Build Command
```bash
sudo bash /mnt/recoverybuild/70-scripts/build.sh
```

## AI Architecture
- Ollama (local) serving 7B model (mistral or qwen2.5-7b preferred)
- Dr. I30LTZ proposes fixes via SSE → user approves → executes
- Android companion connects via SSE on same LAN or Tailscale
- No action executes without user approval

## Security Rules
- No hardcoded credentials
- No open sshd by default
- Tailscale-only remote access
- All AI suggestions require user approval before exec

## Standing Rules (added 2026-10-06, by user)
- **Partition discipline:** all build and install files stay on their own build partition.
  Recovery OS builds/installs live ONLY under /mnt/recoverybuild (installed root /mnt/recoveryos).
  SWARM OS stays on /mnt/Lucy and /mnt/swarmbuild. Never build in /home, /tmp or the dev root.
  **Amended 2026-10-09 (user):** the Recovery *OS ISO* still builds only under /mnt/recoverybuild. That includes the Rust
  `i30ltz-recovery` kiosk program, `native/`, the node agent and the SSE bridge: they are part of Recovery OS. The two
  **phone apps** build on their own partitions and connect to both OSes (SWARM OS and Recovery OS): **Boltz Recovery**
  (the Android I30LTZ Companion) on **/mnt/boltzbuild** (`Boltz Built`, ext4 `6f7c7656-2984-4fb0-81c8-bfc11ca81461`) and
  **Lucille Assistant** on **/mnt/lucillebuild**. The installed Recovery OS root/home is **/mnt/recoveryos**
  (btrfs). Everything an app needs to build (source, toolchain, caches) lives on its own partition, and built apps
  must stand alone (run with no build tree). The ISO build does not consume the phone apps.
- **No secrets, ever:** no API keys, tokens, passwords, private keys or client_secret files in any
  file, commit, log or message. Use .env (gitignored) with .env.example placeholders.
- **Double-check before anything:** before every commit, push, copy into the tree or publish, scan
  the staged/copied files for secrets and confirm none are present. If found, stop and tell the user.
- **Base OS is Debian 13 (trixie)** via live-build. Dev machine is moving from Ubuntu to Debian.
