# I30LTZ Recovery OS: first boot

**v2.0.0 · 2026-09-30** · Ubuntu 24.04 / 26.04 LTS base · **external drive** · assistant: **Dr. I30LTZ "MAD IT"** + access to Lucille

Install Ubuntu LTS onto the **external** drive (USB / portable SSD), boot from
it, then run this kit there. Don't use it on your dev workstation, and don't
use it on SWARM_OS's internal drive. See
[`docs/SUITE_ARCHITECTURE.md`](../../docs/SUITE_ARCHITECTURE.md) for how
Lucille is reached from here.

## Run it

```bash
cd ~/i30ltz-recovery/system/i30ltz-recovery-first-boot
sudo bash first-boot.sh --dry-run      # preview, changes nothing
sudo bash first-boot.sh                # apply (asks y/N once)
sudo bash verify.sh                    # read-only checks, then reboot
```

Options: `--user NAME` (adds that account to the `i30ltz` group), `--only MOD`,
`--skip MOD`, `--enable-ssh` (key-only, needs `--user`), `-y`, `--help`.

## What it does

| Module | Does |
|---|---|
| `00-preflight` | Checks Ubuntu, disk, network, Secure Boot and LUKS; detects the GPU |
| `10-update` | Full upgrade, automatic security updates, firmware check |
| `20-harden` | Firewall blocks all incoming, AppArmor, kernel hardening, no core dumps, SSH off, screen lock, telemetry off |
| `30-performance` | Mesa/Vulkan/VA-API, zram, weekly TRIM. No gaming tuning here |
| `50-recovery-mad-it` | ddrescue, testdisk/photorec, SMART/NVMe, sleuthkit, clamav and more. Private case store `/var/lib/i30ltz/cases` (2770), the `i30ltz-writeblock` helper, and the OS identity file `/etc/i30ltz/release` |
| `90-report` | Dated report in `/var/log/i30ltz-first-boot/` |

Backups of changed files go to `/var/backups/i30ltz-first-boot/`.

## MAD IT write-blocker

```bash
sudo i30ltz-writeblock on /dev/sdb     # patient drive → read-only
sudo ddrescue -d -r3 /dev/sdb /var/lib/i30ltz/cases/case01.img /var/lib/i30ltz/cases/case01.map
sudo i30ltz-writeblock off /dev/sdb
```
