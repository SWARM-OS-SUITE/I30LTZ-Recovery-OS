# system/: first-boot kit

**v2.1.0 · 2026-10-01**

One PC (ThinkPad X13), two separate operating systems. See
[`docs/SUITE_ARCHITECTURE.md`](../docs/SUITE_ARCHITECTURE.md).

> **The real I30LTZ Recovery OS is the image built in [`../os/`](../os/README.md).**
> This kit secures and equips the **Ubuntu USB build machine** that builds
> that image and SWARM_OS. It doesn't turn Ubuntu into the OS.

| Drive | OS | Kit |
|---|---|---|
| **Ubuntu USB (build machine)** | plain Ubuntu, secured; builds I30LTZ OS images + SWARM_OS | [`i30ltz-recovery-first-boot/`](i30ltz-recovery-first-boot/README.md) |
| **boltz (external)** | 🔴 I30LTZ Recovery OS, its own image | built from [`../os/`](../os/README.md) |
| **X13 internal NVMe** | 🟣 SWARM_OS (Arch) + LLcy | not in this repo: it's built *by* Recovery OS from the SWARM_OS repo |

```
system/
├── README.md                        # this map
├── common/                          # shared plumbing (never run directly)
│   ├── runner.sh                    # flags, banner, module loop, summary
│   ├── lib/common.sh                # logging, dry-run, safe writes, backups
│   └── modules/                     # 00-preflight 10-update 20-harden 30-performance 90-report
└── i30ltz-recovery-first-boot/
    ├── first-boot.sh  verify.sh  migrate-to-v2.1.sh  README.md
    └── modules/                     # 40-swarm-builder 50-recovery-mad-it 60-layout
```

History: v1.0.0 mixed both OSes on one install. v2.0.0 added a separate
"dev workstation" kit. v2.1.0 retires that kit, because there's only one PC
and Recovery OS is the SWARM_OS builder.
