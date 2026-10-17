# MOUNTS: canonical map, identical on every OS

Source of truth: `70-scripts/mounts.manifest` (machine-readable). Checker: `70-scripts/check-mounts.sh`
(read-only, any OS). A user timer `mount-check.timer` runs it every 10 min and notifies on problems.
fstab block to paste on every OS: `70-scripts/fstab.canonical`. Verified against live `lsblk` 2026-10-10 (T7 re-partition).

| Mount point | What | FS | Label | UUID | Owner |
|---|---|---|---|---|---|
| `/mnt/storage` | Primary data (inside LUKS `sda4`; unlock first) | ext4 | lucy-master | `2de6ca36-421c-4c3e-8bc4-fbe3e6f66238` | all |
| `/mnt/archive` | Archive / backup of storage (read-only reference) | ext4 | lucy-master-bak | `c400a0ee-6710-4fe7-ad7a-c80dc3f402ca` | all |
| `/mnt/Lucy` | SWARM OS + Lucille build workspace | ext4 | Swarm Build | `62f0e009-43c2-4760-8d6c-d7c445f5f3df` | SWARM |
| `/mnt/swarmbuild` | Mirror/backup of `/mnt/Lucy` | ext4 | swarm-build | `5c84ef0e-d7b8-4b36-b1c4-58817b483dda` | SWARM |
| `/mnt/recoverybuild` | **I30LTZ Recovery OS build workspace** | btrfs | Recovery-build | `a409250b-3973-4448-aeda-94a911538eb4` | RECOVERY |
| `/mnt/downloads` | **Shared downloads, all OSes** (80 GB) | ext4 | downloads | `acde635e-ac49-4bec-ac69-a6b12a2478e4` | all |
| `/mnt/ventoy` | Ventoy USB (ISOs, persistence) | exfat | Ventoy | `5ABB-83DF` | all |
| `/mnt/swarm` | SWARM OS installed root (NVMe p2) | btrfs | swarm-root | `f6f706d0-236a-4f7f-9c6d-948a90a509c5` | SWARM |
| `/mnt/brains` | Lucille/Boltz brains (NVMe p5). Docs also say `/mnt/i30ltz-brains`, `/mnt/boltz`: use `/mnt/brains` | ext4 | i30ltz-brains | `fba1b27f-407b-4385-9dfa-851833f249db` | SWARM |
| `/mnt/recoveryos` | **Recovery OS installed root / home** (Samsung T7, **re-partitioned 2026-10-10**, see the T7 section below; also holds Dr. I30LTZ "MAD AI"'s standalone memory). Replaces `490b9e60-…` and `71287bbf-…` | btrfs | Recovery OS | `96969ed2-15b1-48e6-815e-20fa87d1fb5b` | RECOVERY |
| `/mnt/lucillebuild` | **Lucille Assistant app build** (Go service + Android app). Added 2026-10-09 | ext4 | C. Lucille build | `93037d5a-5b82-484c-ac20-28211c09e1c0` | LUCILLE |
| `/mnt/boltzbuild` | **Boltz Recovery phone-app build** (Android I30LTZ Companion; build partition D). Added 2026-10-09. Created NTFS (`67C2E9F8241FD7AE`) by mistake; the user reformatted it **ext4** in GNOME Disks (so the UUID differs from the `e195839a…` planned earlier). Stale fstab/automount: `sudo /mnt/Lucy/70-scripts/fix_boltzbuild_mount.sh` | ext4 | Boltz Built | `6f7c7656-2984-4fb0-81c8-bfc11ca81461` | BOLTZ |

`/mnt/swarmbuild`, `/mnt/recoverybuild`, `/mnt/lucillebuild` and `/mnt/boltzbuild` are partitions A–D of the same 1.8 TB Micron drive.
Each holds its own source, toolchains and caches; built apps in `dist/` must run with none of them (user, 2026-10-09).
The `/mnt/swarmbuild` label is now `A. swarm-build`, match it by UUID only. Mount the three new ones with
`sudo /mnt/Lucy/70-scripts/apply_app_build_mounts.sh`.

## Samsung T7: the Recovery OS drive (made by the user 2026-10-10; re-made as GPT the same day)
The T7 was cleaned and laid out for Recovery OS alone. The first attempt was MBR, which was a mistake, so it was redone as **GPT with the
same sizes** by `70-scripts/redo-t7-gpt.sh` (run by the user; checked with `lsblk` afterwards). Disk letter varies (`sdb` on 2026-10-10): match by UUID.
It is not mounted, so the filesystem *contents* were not inspected (the three new filesystems are empty by construction).

| Part | Size | FS | Label | UUID / PARTUUID | Use |
|---|---|---|---|---|---|
| 1 EFI | 1000 MiB | vfat | EFI | `2D87-5490` / `952e4e99-72fc-4639-b751-5d8f25f7ed98` | Recovery OS's own **EFI System Partition** (GPT type EFI System), so it boots with zero other drives |
| 2 root | 453.1 GiB | btrfs | Recovery OS | `96969ed2-15b1-48e6-815e-20fa87d1fb5b` / `92e15d58-ee1a-4893-9ecf-0225023d36e2` | `/mnt/recoveryos`: installed root/home **and Dr. I30LTZ "MAD AI"'s standalone memory** |
| 3 swap | 5.9 GiB | swap | swap | `9228d0e1-79d0-41ff-ba1d-dd57af5c2d0d` / `e1ee618c-99f5-41fe-82e6-5cdb5b8cb973` | Recovery OS swap |
| 4 free | 471.6 GiB | none | (GPT name `FREE reserved for a future OS`) | no filesystem / `d5055a4e-6b80-463c-95a4-8f330fd9ca59` | **Kept free on purpose** for a possible future OS (user: "my ambitious self may make one more OS"). Recovery OS does not use it. Never format, shrink or fill it without the user's say-so. It is the last partition, so it can later be grown, shrunk or split. |

The filesystem UUIDs of 1, 2 and 3 are the same as before the redo, so `mounts.manifest` and `fstab.canonical` did not need new values.
Partition 4 used to be a btrfs "empty spce" (`2fa1ca6d-…`); that filesystem is gone, so partition 4 has no `mounts.manifest` row.
The GPT PARTUUIDs above are new; `install-recovery-from-debian.sh` still has the old Micron drive's, see RC-11.

## Per-OS lines (not shared)
`/` and `/boot/efi` differ per OS. The old CachyOS root (`ef9acba2-…`) no longer exists. Recovery OS's EFI is the T7's own
`2D87-5490`; the old `A367-87E3` is not present in `lsblk` any more.
**Fixed 2026-10-10 (by the user, with sudo):** this machine's `/etc/fstab` line 40 used to map `/mnt/recoveryos` to `/dev/sda2` (the dev Debian root, not the T7); it now uses the canonical UUID line. Backup: `/etc/fstab.bak-2026-10-10`. The old `/dev/sda2` mount stays live until it is unmounted (`sudo umount /mnt/recoveryos`) or the machine reboots; the checker reports a CONFLICT until then.
Dev machine `/` is `sdb2` (`2731e68a-…`) today; it becomes Debian.

## Rules
1. Same path on all OSes; mount by **UUID**, options `defaults,nofail,x-systemd.automount`.
2. A missing drive must never block boot (`nofail`). SWARM OS and Recovery OS must boot with zero extra drives.
3. When a drive is reformatted its UUID changes: update `mounts.manifest`, this file, and `fstab.canonical` the same day.
4. Run `check-mounts.sh` at the start of any session and after any disk change.
