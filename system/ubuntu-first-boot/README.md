# Ubuntu First Boot: SWARM_OS + I30LTZ Recovery

**v1.0.0 · 2026-09-30** · Ubuntu 24.04 / 26.04 LTS

This kit takes a fresh Ubuntu install and turns it into a locked-down base for
both halves of the suite:

| Profile | Makes | Assistant |
|---|---|---|
| `swarm` | SWARM_OS for daily life, gaming and coding | LUCILLE CORE AI "LLcy" |
| `recovery` | I30LTZ Recovery OS for PC repair and data recovery | Dr. I30LTZ "MAD IT" |
| `both` (default) | both on one machine | both |

## Run it (3 commands)

```bash
cd ~/SWARM_OS/30-source/i30ltz-recovery/system/ubuntu-first-boot   # or wherever you cloned it
sudo ./first-boot.sh --dry-run      # 1. preview only, nothing changes
sudo ./first-boot.sh                # 2. apply (asks y/N once)
sudo ./verify.sh && sudo reboot     # 3. check everything, then reboot
```

Other options:

```bash
sudo ./first-boot.sh --profile swarm        # only SWARM_OS / LLcy
sudo ./first-boot.sh --profile recovery     # only I30LTZ / MAD IT
sudo ./first-boot.sh --only 20-harden       # re-run one module
sudo ./first-boot.sh --skip 30-performance
sudo ./first-boot.sh --enable-ssh           # remote login, keys only (off by default)
sudo ./first-boot.sh --help
```

You can run it again safely. Before it changes any system file it makes a
timestamped copy in `/var/backups/swarm-first-boot/`. Logs and a dated report
go to `/var/log/swarm-first-boot/`.

## What each module does

| Module | Does |
|---|---|
| `00-preflight` | Checks the Ubuntu version, free disk, network, Secure Boot and LUKS encryption, and detects the GPU |
| `10-update` | Full upgrade, **automatic security updates**, firmware checks (fwupd) |
| `20-harden` | Firewall blocks all incoming, AppArmor on, kernel and network hardening, no core dumps, private home folder, SSH **off** unless you ask, screen locks after 10 min, telemetry off |
| `30-performance` | Mesa, Vulkan and hardware video decode for **integrated Intel/AMD graphics**, 32-bit libraries for Proton, zram (zstd), game-ready `vm.max_map_count`, smoother disk writes, weekly TRIM |
| `40-swarm-lucille` | Rust (rustup), clang, cmake, Python, gamemode, MangoHud. Creates `/opt/swarm_os` and `/etc/swarm_os/lucille.toml`. LLcy listens on **loopback only** |
| `50-recovery-mad-it` | ddrescue, testdisk/photorec, SMART and NVMe tools, sleuthkit, foremost, clamav and more. Creates `/opt/i30ltz`, a private case store `/var/lib/i30ltz/cases` (mode 2770) and the **`i30ltz-writeblock`** helper |
| `60-layout` | Creates numbered folders in `~/SWARM_OS/` (00-inbox … 90-archive) |
| `90-report` | Writes a dated report of the finished machine |

## MAD IT write-blocker

Don't write to a drive you're recovering from. Lock it first:

```bash
sudo i30ltz-writeblock status /dev/sdb
sudo i30ltz-writeblock on /dev/sdb     # whole disk + partitions read-only
sudo ddrescue -d -r3 /dev/sdb /var/lib/i30ltz/cases/case01.img /var/lib/i30ltz/cases/case01.map
sudo i30ltz-writeblock off /dev/sdb
```

## Things the kit won't do for you

- **Encrypt the disk.** That has to happen during install: choose *Advanced → Encrypt with LUKS*. Preflight warns you if it's missing.
- **Turn on Secure Boot.** That's a firmware setting. Preflight warns you if it's off.
- **Accept Steam's license.** When you're ready, run `sudo apt install steam-installer`.
- **Download AI models.** Put LLcy models in `/opt/swarm_os/lucille/models/` and MAD IT's in `/opt/i30ltz/models/`.
- **Turn off Safe Browsing or download protections.** The older `imports/.../i30ltz-setup.sh` did this. This kit leaves them on.

## Layout

```
system/ubuntu-first-boot/
├── first-boot.sh        # runner: flags, banner, module loop, summary
├── verify.sh            # read-only checks
├── lib/common.sh        # logging, dry-run, safe file writes, apt helpers
└── modules/             # run in number order
    ├── 00-preflight.sh
    ├── 10-update.sh
    ├── 20-harden.sh
    ├── 30-performance.sh
    ├── 40-swarm-lucille.sh
    ├── 50-recovery-mad-it.sh
    ├── 60-layout.sh
    └── 90-report.sh
```
