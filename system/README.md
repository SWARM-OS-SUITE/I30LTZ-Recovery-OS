# system/: first-boot kits

**v2.0.0 · 2026-09-30**

SWARM_OS (Arch, internal) and I30LTZ Recovery OS (Ubuntu, external) are **two
separate operating systems** (see [`docs/SUITE_ARCHITECTURE.md`](../docs/SUITE_ARCHITECTURE.md)), so
each machine gets its own kit. Never run two kits on the same machine.

| Machine | Kit | Assistant |
|---|---|---|
| The **external** drive that **is** I30LTZ Recovery OS (Ubuntu base) | [`i30ltz-recovery-first-boot/`](i30ltz-recovery-first-boot/README.md) | Dr. I30LTZ "MAD IT" |
| Your **dev workstation**, the Ubuntu laptop that builds both OSes | [`dev-workstation-first-boot/`](dev-workstation-first-boot/README.md) | none (it's neither OS) |
| The **internal** drive that **is** SWARM_OS (Arch/archiso) | not in this repo: it belongs in the SWARM_OS / Lucille repo | LUCILLE CORE AI "LLcy" |

```
system/
├── README.md                        # this map
├── common/                          # shared by both kits (never run directly)
│   ├── runner.sh                    # flags, banner, module loop, summary
│   ├── lib/common.sh                # logging, dry-run, safe writes, backups
│   └── modules/                     # 00-preflight 10-update 20-harden 30-performance 90-report
├── i30ltz-recovery-first-boot/      # I30LTZ Recovery OS
│   ├── first-boot.sh  verify.sh  README.md
│   └── modules/50-recovery-mad-it.sh
└── dev-workstation-first-boot/      # the laptop that builds both OSes
    ├── first-boot.sh  verify.sh  migrate-from-v1.sh  README.md
    └── modules/40-dev-toolchain.sh  50-recovery-test-bench.sh  60-layout.sh
```

v1.0.0 (`system/ubuntu-first-boot/`, `--profile both`) mixed the two OSes on
one machine. It was replaced by these kits. If you ran v1, see
`dev-workstation-first-boot/README.md`, section "Upgrading from v1.0.0".
