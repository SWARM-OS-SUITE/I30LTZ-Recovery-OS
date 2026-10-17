# I30LTZ RECOVERY OS
**Version:** 0.1.0-alpha  
**Date:** 2026-10-05  
**Build Root:** /mnt/recoverybuild  

---

## Overview

Debian-based AI-native recovery OS with integrated diagnostics, data recovery, OS repair, and telemetry.  
AI Assistant: **Dr. I30LTZ** ("THE MAD DR.") — powered by local Ollama (7B max, integrated GPU).

## Components

| Component | Path | Status |
|-----------|------|--------|
| Debian ISO Profile (live-build) | `40-iso-profile/` | 🔴 WIP |
| Recovery app (Rust, merged from i30ltz-recovery) | `30-source/i30ltz-recovery/` | 🔴 WIP |
| Dr. I30LTZ AI Backend | `30-source/mad-dr-ai/` | 🔴 WIP |
| Enterprise Repair App | `30-source/enterprise-app/` | 🔴 WIP |
| Android Companion (I30LTZ Companion) | `/mnt/boltzbuild/src/I30LTZ-Recovery-companion/` (build partition D) | 🟡 see CP rows |
| Build Scripts | `70-scripts/` | 🔴 WIP |
| Ollama / AI Brain | `60-brain/` | 🔴 WIP |

> Live status of every item: `00-CURRENT/MASTER_BUILD_LIST.md`.

## Design Goals

- **Minimal hardware** — runs on integrated graphics, 7B LLM max
- **Secure by default** — no open ports, no default passwords
- **AI-native** — Dr. I30LTZ proposes fixes; user approves before execution
- **Android companion** — SSE connection for remote control/monitoring
- **Enterprise grade** — fixes failing OSes, data recovery, diagnostics, telemetry, optimization

## Directory Layout

```
/mnt/recoverybuild/
├── 00-CURRENT/          # Active build state & tracker
├── 10-releases/         # Stamped ISO releases
├── 20-runtime/          # fstab, services, env configs
├── 30-source/           # All source code
│   ├── debiso/          # live-build chroot hooks & config
│   ├── mad-dr-ai/       # Dr. I30LTZ AI (Python/Ollama)
│   ├── enterprise-app/  # Electron/Next.js repair frontend
├── 40-iso-profile/      # live-build lb config tree
├── 50-backends/         # Ollama model configs
├── 60-brain/            # MAD AI brain / agent logic
├── 70-scripts/          # build.sh, install.sh, recover.sh
├── 80-vm/               # QEMU/KVM test configs
├── 90-docs/             # Architecture & runbooks
└── 99-archive/          # Old builds / backups
```

## Quick Start (Build)

```bash
cd /mnt/recoverybuild
sudo bash 70-scripts/build.sh
```

---

*I30LTZ RECOVERY OS — Built by i30ltz | Athens, GA*
