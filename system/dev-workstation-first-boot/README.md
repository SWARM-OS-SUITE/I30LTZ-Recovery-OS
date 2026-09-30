# SWARM_OS Suite dev workstation: first boot

**v2.0.0 · 2026-09-30** · Ubuntu 24.04 / 26.04 LTS

This kit is for the laptop you use to **build both operating systems**:

- **SWARM_OS**, the Arch/archiso OS on the internal drive, with LUCILLE CORE AI "LLcy"
- **I30LTZ Recovery OS**, the Ubuntu-based OS on an external drive, with Dr. I30LTZ "MAD IT"

This machine is **neither** OS. It never writes `/etc/swarm_os/release` or
`/etc/i30ltz/release`. Its role file is `/etc/suite-dev/release`.

## Run it

```bash
cd ~/i30ltz-recovery/system/dev-workstation-first-boot
sudo bash first-boot.sh --dry-run --user YOURNAME   # preview
sudo bash first-boot.sh --user YOURNAME             # apply
sudo bash verify.sh                                 # read-only checks, then reboot
```

## What it does

| Module | Does |
|---|---|
| `00`–`30` (shared) | Same security and performance setup as the Recovery OS kit, **plus gaming tuning** (i386 libs for Proton, `vm.max_map_count`) |
| `40-dev-toolchain` | Rust, clang, cmake, Python. **QEMU + OVMF** to boot-test both ISOs in a window. `arch-install-scripts` (SWARM_OS) and `debootstrap`/`live-build` (Recovery OS). gamemode, MangoHud. Creates `/opt/suite-dev/{models,iso-test}` |
| `50-recovery-test-bench` | The same MAD IT tools as the Recovery OS, as a test bench, **without** the OS identity |
| `60-layout` | `~/SWARM_OS/`: 40- is the SWARM_OS project, 50- is the I30LTZ project, and they stay separate |
| `90-report` | Dated report in `/var/log/dev-workstation-first-boot/` |

## Upgrading from v1.0.0

v1.0.0 set this laptop up as if it were both OSes. Fix it in 3 steps:

```bash
cd ~/i30ltz-recovery && git checkout main && git pull
cd system/dev-workstation-first-boot
sudo bash migrate-from-v1.sh --dry-run    # see what changes
sudo bash migrate-from-v1.sh              # rename configs, drop the fake OS identity files
sudo bash first-boot.sh --user YOURNAME   # adds QEMU, the role file, etc.
sudo bash verify.sh
```

The migration keeps every setting and every tool, and backs up everything it
touches. It renames `60-swarm-*` config files to `60-firstboot-*`, removes
`/etc/swarm_os/release`, `/etc/swarm_os/lucille.toml` and
`/etc/i30ltz/release`, and deletes the v1 `/opt/swarm_os` folders only if
they're empty. Your `~/SWARM_OS` folders are not touched.
