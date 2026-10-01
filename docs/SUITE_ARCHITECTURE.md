# SWARM_OS Suite: architecture

**v1.1.0 · 2026-10-01** · the source of truth for which OS is which.
If another file disagrees with this one, this one wins. Fix the other file.

## One PC, two operating systems

There's **one PC**, the Lenovo ThinkPad X13 Gen 1, and it has **two separate
operating systems**:

| | 🟣 **SWARM_OS** | 🔴 **I30LTZ Recovery OS** |
|---|---|---|
| **Base** | **Arch Linux** (built with archiso) | **Ubuntu LTS** (its own separate install) |
| **Lives on** | X13 **internal NVMe** | **External drive "boltz"** (boots from USB) |
| **AI assistant** | **LUCILLE CORE AI "LLcy"** | **Dr. I30LTZ "MAD IT"**, plus access to **Lucille** |
| **Job** | Daily life, gaming, coding | Repair, data recovery, and **building SWARM_OS** |
| **Repo** | SWARM_OS / Lucille repo | **this repo** (`i30ltz-recovery`) |
| **Setup kit** | lives in the SWARM_OS repo | [`system/i30ltz-recovery-first-boot/`](../system/i30ltz-recovery-first-boot/README.md) |

Rules:
1. **Never mix them.** SWARM_OS never gets Recovery OS packages or identity,
   and Recovery OS never gets SWARM_OS identity.
2. **Recovery OS stays on boltz**, never on the internal NVMe. That way it
   still works when SWARM_OS, the NVMe, or the bootloader is broken.
3. **Only one OS runs at a time.** You pick one at boot: the internal drive
   means SWARM_OS, and boltz means Recovery OS (press **F12** on the X13 for the
   boot menu).
4. **Recovery OS builds SWARM_OS.** The builder lives on a different drive
   from what it builds, so a bad build can never strand you. This is the
   plan from the 2026-09-18 tracker entry.

There is no third "dev workstation". The Ubuntu install in use on
2026-09-30/10-01 is **temporary**. Once boltz Recovery OS works, it retires.

```mermaid
flowchart LR
  subgraph X13["💻 ThinkPad X13 Gen 1"]
    subgraph NVME["💽 Internal NVMe"]
      SW["🟣 SWARM_OS · Arch"]
      LU["🤖 LUCILLE CORE AI (LLcy)<br/>LucyServer 127.0.0.1:5000"]
      SW --- LU
    end
  end
  subgraph BOLTZ["🔌 External drive: boltz"]
    RO["🔴 I30LTZ Recovery OS · Ubuntu"]
    MAD["🩺 Dr. I30LTZ 'MAD IT'"]
    BLD["🏗️ SWARM_OS builder<br/>Arch container → mkarchiso"]
    VM["🧪 QEMU test boot"]
    DATA["🗄️ boltz data partition<br/>Lucille-AI + I30LTZ copies"]
    RO --- MAD
    RO --- BLD --> VM
    RO --- DATA
  end
  BOLTZ -- "F12 boot when SWARM_OS is down" --> X13
  VM -- "tested ISO → you install it" --> NVME
  RO -. "mounts SWARM_OS READ-ONLY<br/>to repair + read Lucille data" .-> NVME
  MAD <-- "LUCY_URL=127.0.0.1:5000" --> DATA
```

## The boltz drive layout

```
boltz (external)
├── EFI partition            ← Recovery OS bootloader
├── Recovery OS root         ← Ubuntu LTS + I30LTZ kit (fresh install)
└── boltz data partition     ← EXISTING: /mnt/boltz (Lucille-AI, I30LTZ-Recovery copies)
                               KEEP IT. The Ubuntu installer must not format it.
```

When you install Ubuntu onto boltz:
1. **Back up the data partition first**, for example to a second USB stick.
2. In the installer, choose **manual partitioning** ("Something else"). Never
   choose "Erase disk", because that would wipe the data partition.
3. Pick **boltz**, not the X13's NVMe. Check names and sizes twice.
4. Put the bootloader on **boltz** too, so the X13's internal disk is never touched.

## Building SWARM_OS from Recovery OS

```bash
i30ltz-disks                                            # which disk is which (read-only)
swarm-build ~/SWARM_OS/30-source/swarm-os/<profile>     # Arch container → ISO
swarm-test-iso /var/lib/i30ltz/swarm-build/out/<iso>    # UEFI VM, real disks NOT attached
```
- `swarm-build` runs `mkarchiso` inside an `archlinux` container (podman).
  Builds only touch `/var/lib/i30ltz/swarm-build/` on boltz, and every ISO
  gets a `.sha256` file.
- `swarm-test-iso` boots the ISO in a QEMU UEFI VM with a throwaway virtual disk.
- **Installing to the NVMe is always a manual, deliberate step** using the
  SWARM_OS installer. No script in this repo writes to the internal drive.

## Lucille has to work from Recovery OS

You need Lucille most when SWARM_OS won't boot, so Recovery OS provides it in
two ways:

### A. Portable Lucille on boltz (default)
- The Lucille runtime (`lucy-server`, config and models) is read from the
  **boltz data partition**, which already holds the Lucille-AI copies, and
  served on **`127.0.0.1:5000` only**. That's the same port and API as on
  SWARM_OS, so Dr. I30LTZ uses `LUCY_URL=http://127.0.0.1:5000`.
- It works even when the NVMe is dead or locked, and it never writes to the
  drive being repaired.
- It's refreshed from SWARM_OS on purpose (a checksummed sync), never
  automatically during a repair.

### B. Your real Lucille data from the NVMe (read-only)
- Recovery OS can unlock (LUKS) and mount SWARM_OS **read-only**, so Lucille
  can read your real memory and notes. Anything it writes goes to boltz.
- Skip this if the NVMe is failing. Image it first
  (`i30ltz-writeblock on` + `ddrescue`) and use the image instead.

### Safety rules
- Loopback only. The firewall blocks all incoming traffic, and Lucille never
  listens on the network.
- The NVMe is read-only by default. Repairs and installs are deliberate
  actions you choose, never side effects.
- No secrets in this repo. Tokens are generated per machine at first boot.

## Status (2026-10-01)

| Item | State |
|---|---|
| Recovery OS first-boot kit (Ubuntu) + SWARM_OS builder | ✅ built · v2.1.0 (not yet run on boltz) |
| boltz Recovery OS install | 🔄 **in progress** (fresh Ubuntu install by you) |
| Temporary Ubuntu in use now | ⏳ retire once boltz works |
| Portable Lucille (A) | ⏳ planned: `lucille-portable` module reading the boltz data partition |
| Read-only SWARM_OS mount for Lucille data (B) | ⏳ planned |
| `native/` Rust app retarget, Debian 12 → Ubuntu LTS | ⚠️ to do |
| SWARM_OS itself (archiso profile, Lucille services) | lives in the SWARM_OS repo |
