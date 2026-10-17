# Dr. Boltz <-> Lucille bridge worker

`boltz_bridge.py` is Dr. Boltz's side of the bridge to Lucille Assistant (`/mnt/lucillebuild`, port 8403). Full guide, permissions, root and
limits: `/mnt/lucillebuild/src/LucilleAssistant/README.md` -> "Dr. Boltz bridge".

```bash
lucille-assistant pair --role agent            # on the PC: prints a one-time code
python3 boltz_bridge.py pair CODE              # stores the token in ~/.config/boltz-bridge/token (mode 600)
python3 boltz_bridge.py status                 # git, bwrap, socat, claude, repos, limits
python3 boltz_bridge.py run                    # works until Ctrl-C; `run --once` does one pass
python3 -I -m unittest discover -s . -p 'test_*.py'   # 37 tests, real git and the real sandbox
```

Rules this file follows (set by the user): no secrets in code or tests (test credentials are built at run time); work happens in git worktrees on
`boltz/cNNNN` branches, never in a main checkout (the `recovery-drive-sync` job runs `git add -A` there and pushes); nothing here pushes; a
person approves every merge and every root action; the coding engine runs in a sandbox with no network and no `sudo`.
The worker is standard library only. `boltz-bridge.service` is a user unit; it is **not** enabled, because a worker that spends model usage
should start only when you say so.
