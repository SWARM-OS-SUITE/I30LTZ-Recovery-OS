# I30LTZ Recovery — Build Tracker

> **Official names (exact capitalization, used everywhere — code, UI, docs, services):**
> AI identity →  **DR. I30LTZ** "The Mad DR."   |   Program → **I30LTZ Recovery**   |   Suite → **SWARM OS**

Auto-refreshed by `70-scripts/update_build_tracker.sh`. Run it after every build.

---

## Component Registry

_Last updated: 2026-09-14 17:12_

### UI Layer

| Component | Language | Version | Built | Size | SHA256 (first 16) |
|---|---|---|---|---|---|
| DR. I30LTZ Recovery | Rust + Raylib | 0.1.0 | 2026-09-12 12:36 | 2.7M | `cc8e005f6fc56557` |
| Lucille Panel (swarm-slint) | Rust + Slint | 6.2.50 | 2026-09-13 19:04 | 42M | `4135782f9861d423` |
| Flutter Shell (frontend) | Dart / Flutter | 6.2.50+50 | — | — | staged in ISO |

### Backend Services

| Component | Language | Version | Built | Size | SHA256 (first 16) | Port |
|---|---|---|---|---|---|---|
| LucyServer-go | Go 1.26 | 6.2.50 | 2026-09-13 19:04 | 14M | `aaecf49c07608d15` | 5000 |
| GamingAgent-go | Go 1.23 | 6.2.50 | 2026-09-13 19:04 | 18M | `da631d57189e7eec` | 8401 |
| GoogleWorkspaceService | .NET 10 / C# | 6.2.50 | ISO build | — | staged in ISO | 5002 |
| lucille-core | C++20 | — | 2026-09-08 18:22 | 628K | `050a37521867a268` | native lib |

### ISO / OS

| Component | Version | Date | Notes |
|---|---|---|---|
| SWARM OS ISO | 6.2.50 | 2026-09-14 17:12 | `10-releases/` — auto-bumped on build |
| Arch packages.x86_64 | — | 2026-09-12 | aspnet-runtime-10.0 added |

### Scripts

| Script | Last Updated | Notes |
|---|---|---|
| `build_swarm_iso_6.2.19_2026-09-08.sh` | 2026-09-15 | Builds all components + ISO; Step 8 syncs to Ventoy, keeps 2 local / 10 Ventoy |
| `snapshot_before_update.sh` | 2026-09-15 | **Run before deploying any change** — Btrfs snapshot + GRUB rollback entry |
| `sync_lucille_ai.sh` | 2026-09-12 | rsync --checksum, Lucille-AI + I30LTZ-Recovery |
| `update_build_tracker.sh` | 2026-09-12 | Regenerates this file |
| `unlock_slick.sh` | 2026-09-12 | Opens LUKS slick partition |
| `install_swarm_os.sh` | 2026-09-15 | Live USB → NVMe installer; enables swarm-snapshot.service |

---

## Binary Locations by OS

One PC, one OS at a time. sdb8 (`/mnt/boltz`) is mounted by all three.

| OS | Boot Drive | DR. I30LTZ Recovery | LucyServer | Notes |
|---|---|---|---|---|
| SWARM OS | nvme0n1p4 | `/opt/swarm_os/i30ltz-recovery` | `/opt/swarm_os/LucyServer/lucy-server` | Primary OS |
| Endeavor | sdb4 (Ventoy) | `/mnt/boltz/I30LTZ-Recovery/i30ltz-recovery` | bring up LucyServer manually | Recovery boot |
| CachyOS | nvme0n1p1 | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` | build from source or use boltz drive | Daily driver |

**All three mount sdb8 → `/mnt/boltz`** for shared AI binary + Lucille-AI reference.

---

## Sync Status

| Target | Path | Method | Last Synced |
|---|---|---|---|
| sdb8 (`/mnt/boltz`) | `/mnt/boltz/Lucille-AI/` | `rsync -a --checksum --no-delete` | see log below |
| sdb8 (`/mnt/boltz`) | `/mnt/boltz/I30LTZ-Recovery/` | `rsync -a --checksum` + sha256 manifest | see log below |
| sda4 (lucy-master LUKS) | `/mnt/lucy-master-backup/Lucille-AI/` | same | only when LUKS unlocked |
| sda4 (lucy-master LUKS) | `/mnt/lucy-master-backup/I30LTZ-Recovery/` | same | only when LUKS unlocked |

### Verify Integrity (any OS after mounting sdb8)

```bash
sha256sum -c /mnt/boltz/I30LTZ-Recovery/SYNC_MANIFEST.sha256
```

### Run DR. I30LTZ Recovery

```bash
# From sdb8 (Endeavor / CachyOS):
LUCY_URL=http://127.0.0.1:5000 SWARM_AUTH_TOKEN=swarm-token-2026 \
  /mnt/boltz/I30LTZ-Recovery/i30ltz-recovery

# From SWARM OS (via systemd):
systemctl start i30ltz-recovery

# Build from source:
cd /mnt/Lucy/30-source/i30ltz-recovery && cargo build --release
```

---

## UI Version Labels

Every UI surface displays its version + build date. Do not omit these.

| Surface | Where displayed | Format |
|---|---|---|
| DR. I30LTZ Recovery header | top-right corner | `v0.1.0  \|  2026-09-12` |
| DR. I30LTZ Recovery footer | bottom-right | `DR. I30LTZ Recovery  v0.1.0  \|  2026-09-12` |
| SWARM OS lock screen | bottom of screen | version from Flutter `pubspec.yaml` |
| Lucille Panel (slint) | status bar | `SWARM_VERSION` baked at compile time |
| LucyServer `/api/version` | REST endpoint | returns build version + date |

---

## Before Deploying a New Binary

Always snapshot the installed SWARM OS root before pushing a new I30LTZ Recovery build:

```bash
# Desktop shortcut — double-click:
# /home/i30ltz/Desktop/swarm-snapshot.desktop
# (Right-click → Allow Launching on first use)

# Or terminal:
sudo /mnt/Lucy/70-scripts/snapshot_before_update.sh pre-i30ltz-recovery

# Then copy the new binary to the installed system:
sudo cp /mnt/Lucy/30-source/i30ltz-recovery(seperate-related-project)/target/release/i30ltz-recovery \
     /mnt/swarm/@/opt/swarm_os/i30ltz-recovery
```

Rollback: reboot → GRUB → pick `"SWARM OS — Snapshot …"` entry.

> **Keep desktop script current:** the `.desktop` file calls `snapshot_before_update.sh`
> by absolute path. If the script moves, update the `Exec=` line in
> `/home/i30ltz/Desktop/swarm-snapshot.desktop`.

---

## Build Commands (Reference)

```bash
# DR. I30LTZ Recovery (bakes BUILD_DATE at compile time):
cd /mnt/Lucy/30-source/i30ltz-recovery && cargo build --release

# All components + ISO:
/mnt/Lucy/70-scripts/build_swarm_iso_6.2.19_2026-09-08.sh

# Sync all binaries to sdb8 + sda4 with checksums:
sudo /mnt/Lucy/70-scripts/sync_lucille_ai.sh

# Regenerate this build tracker:
/mnt/Lucy/70-scripts/update_build_tracker.sh
```

---

## Sync Log

_Appended by `sync_lucille_ai.sh` on each run._

### Sync — 2026-09-12 20:54:07
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-12 21:54:07
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-12 22:54:07
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-12 23:54:09
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-13 00:54:09
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-13 01:54:10
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-13 02:54:10
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-13 12:16:33
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-13 07:38:11
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-13 11:55:08
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-13 12:40:46
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-13 17:25:00
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 00:08:05
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 00:19:10
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 01:19:21
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 02:20:01
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 03:20:21
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 04:20:27
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 05:20:31
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 02:45:34
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 04:34:02
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 05:10:20
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |

### Sync — 2026-09-15 05:20:16
| Field | Value |
|---|---|
| Binary | `/mnt/Lucy/30-source/i30ltz-recovery/target/release/i30ltz-recovery` |
| SHA256 | `cc8e005f6fc565570873224170c4a5f4878519cd3a97feb57ec0dd1b6740f089` |
| Size | 2801864 bytes |
| sdb8 (/mnt/boltz) | ✓ synced |
| sda4 (lucy-master) | not mounted / LUKS locked |
