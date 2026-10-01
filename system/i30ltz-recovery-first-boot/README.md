# I30LTZ Recovery OS: first boot

**v2.1.0 · 2026-10-01** · Ubuntu 24.04 / 26.04 LTS · **external USB drive** ·
assistant **Dr. I30LTZ "MAD IT"** + access to Lucille · **builds SWARM_OS**

Run this on the **external Ubuntu drive** that is Recovery OS. That can be
the Ubuntu you already boot from USB or a fresh install. Never run it on
SWARM_OS (the X13's internal NVMe). See
[`docs/SUITE_ARCHITECTURE.md`](../../docs/SUITE_ARCHITECTURE.md) for the
boltz data rules and how Lucille is reached from here.

## Run it

```bash
sudo apt install -y git
git clone https://github.com/cledford955-maker/i30ltz-recovery.git ~/SWARM_OS/30-source/i30ltz-recovery
cd ~/SWARM_OS/30-source/i30ltz-recovery/system/i30ltz-recovery-first-boot
sudo bash first-boot.sh --dry-run --user "$USER"      # preview, changes nothing
sudo bash first-boot.sh --user "$USER"                # apply (asks y/N once)
sudo bash verify.sh                                   # read-only checks, then reboot
```
The repo is private, so cloning asks you to sign in. `gh auth login` is the easiest way.

### Already ran an older kit on this Ubuntu? Clean up first

If this Ubuntu ran kit v1.0.0 (`--profile both`) or v2.0.0 (dev
workstation), remove the leftover SWARM_OS labels before running the kit:
```bash
sudo bash migrate-to-v2.1.sh --dry-run    # preview
sudo bash migrate-to-v2.1.sh              # renames configs, removes fake labels, backs up everything
```
It keeps every setting, tool, Flatpak app (GeForce NOW) and your
`~/SWARM_OS` folders.

## What it does

| Module | Does |
|---|---|
| `00-preflight` | Checks Ubuntu, disk, network, Secure Boot and LUKS; detects the GPU |
| `10-update` | Full upgrade, automatic security updates, firmware check |
| `20-harden` | Firewall blocks all incoming, AppArmor, kernel hardening, no core dumps, SSH off, screen lock, telemetry off |
| `30-performance` | Mesa/Vulkan/VA-API (Intel non-free decoder with a free fallback), zram, weekly TRIM |
| `40-swarm-builder` | podman + QEMU + OVMF and three helpers: **`swarm-build`**, **`swarm-test-iso`**, **`i30ltz-disks`** |
| `50-recovery-mad-it` | ddrescue, testdisk/photorec, SMART/NVMe, sleuthkit, clamav and more. Private case store (2770), `i30ltz-writeblock`, and `/etc/i30ltz/release` |
| `60-layout` | `~/SWARM_OS/` numbered folders (needs `--user`) |
| `90-report` | Dated report in `/var/log/i30ltz-first-boot/` |

## Build + test SWARM_OS

```bash
i30ltz-disks                                              # which disk is which, read-only
swarm-build ~/SWARM_OS/30-source/swarm-os/<profile>       # dir that holds profiledef.sh
swarm-test-iso /var/lib/i30ltz/swarm-build/out/<file>.iso # UEFI VM, real disks not attached
swarm-test-iso <file>.iso --fresh-disk --ram 6144         # wipe the virtual disk, more RAM
```
Installing a tested ISO onto the X13's NVMe is a manual step you do with the
SWARM_OS installer. No script here writes to the internal drive.

## MAD IT write-blocker

```bash
sudo i30ltz-writeblock on /dev/nvme0n1     # patient drive → read-only
sudo ddrescue -d -r3 /dev/nvme0n1 /var/lib/i30ltz/cases/case01.img /var/lib/i30ltz/cases/case01.map
sudo i30ltz-writeblock off /dev/nvme0n1
```
