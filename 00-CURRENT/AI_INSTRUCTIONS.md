# AI INSTRUCTIONS: read this first, every session, every AI (Claude, Codex, Gemini, any)

Applies to all four projects (SWARM OS, I30LTZ Recovery OS, I30LTZ Companion, Lucille Assistant)
and all four OSes (dev Ubuntu→Debian, CachyOS, SWARM OS, Recovery OS). Same rules everywhere.
This file lives at `/mnt/recoverybuild/00-CURRENT/AI_INSTRUCTIONS.md`: the same path on every OS.

## 1. Start of session (2 minutes)
1. `bash /mnt/recoverybuild/70-scripts/check-mounts.sh`: if anything prints PROBLEMS, tell the user before working.
2. `bash /mnt/recoverybuild/70-scripts/ai-board.sh list`: see who is working where.
3. Read `MASTER_BUILD_LIST.md` for the project you were asked to touch.
4. **Claim your area** before editing: `ai-board.sh claim <your-name> <path-or-ID> "<task>"`.
   If it reports OVERLAP, stop and ask the user. Two AIs editing one area has already caused duplicated work.
5. Finish with `ai-board.sh done <your-name> <area> "<what changed>"`.

## 2. Ownership: stay in your lane
| Area | Owner | Others may |
|---|---|---|
| `/mnt/recoverybuild` (Recovery OS), `/mnt/boltzbuild` (Boltz Recovery phone app = Companion) | Recovery AI | read; propose via the board |
| `/mnt/Lucy`, `/mnt/swarmbuild` (SWARM OS, Lucille Assistant, Apex IDE) | SWARM AI | read; propose via the board |
| `00-CURRENT/*` shared docs | whoever holds a claim | append ideas with `ai-board.sh idea` |
`/run/media/*/lucy-master` and `/mnt/archive`, `/mnt/storage` are **read-only reference**. Never write there.

## 3. Hard rules (set by the user, 2026-10-06)
- **Partition discipline.** All building and installing happens only on the project's own build partition
  (Recovery → `/mnt/recoverybuild`, installed root `/mnt/recoveryos`; SWARM → `/mnt/Lucy`, `/mnt/swarmbuild`).
  Never build in `/home`, `/tmp`, or the dev machine's root. ISOs go only where `ISO_RELEASE_POLICY.md` says.
- **No secrets, ever.** No API keys, tokens, passwords, private keys, `client_secret*`, `.env` contents in
  any file, commit, log, doc, chat message or screenshot. Use `.env` (gitignored) + `.env.example` placeholders.
  The default token `swarm-token-2026` is public; never use it for real.
- **Double-check before anything.** Before every commit, push, copy into a repo, or publish: scan what you are
  about to add for secrets (keys like `sk-`, `AIza`, `ghp_`, `AKIA`, `-----BEGIN ... PRIVATE KEY`, password-looking
  assignments). If you find one, stop and tell the user. Never print a suspected secret; say file and line only.
- **Mount points are identical on every OS** and mounted by UUID (`70-scripts/mounts.manifest`, `MOUNTS.md`).
  Never use `/dev/sdX` or `by-id` paths in configs, scripts or docs. Disk letters change between boots.
- **No destructive action without the user.** No `rm -rf`, `mkfs`, reformat, `dd`, force-push, or deleting a
  drive's data unless the user said so for that exact target. Look at the target first; verify copies by checksum.
- **User approval gates the OS products too.** Dr. I30LTZ / Lucille never execute a fix, install or write to a
  drive without explicit user approval; the internal drive is mounted read-only by default; image failing drives first.
- **Local-first.** Recovery OS must repair with zero external drives and no cloud (7B model max, integrated GPU).
- **Write for the next AI.** Short entries, with file paths. Say honestly what was *verified* versus *only written*.

## 4. Where things go
| Thing | Location |
|---|---|
| New task / bug / plan | `MASTER_BUILD_LIST.md` (ID, priority, status, source) |
| New idea or add-on | `ai-board.sh idea <ai> "<idea>"` → Idea inbox (never lose one) |
| Finished-work history | SWARM: `SWARM_AI_FEATURES.md` · Recovery: git log + `CONSOLIDATION_LOG.md` |
| Downloads (installers, tarballs) | `/mnt/downloads/<os-or-topic>/` |
| Backups of home/secrets | encrypted, off every build partition, never in git |
| Mount / disk facts | `MOUNTS.md` + `70-scripts/mounts.manifest` (update both, run the checker) |

## 5. Per-project quick facts
- **SWARM OS**: Arch/archiso; Lucille Core AI "LLcy"; read `/mnt/Lucy/CLAUDE.md` and `AGENTS.md`; ISOs → Ventoy only.
- **I30LTZ Recovery OS**: Debian 13 trixie + live-build; Dr. I30LTZ "MAD AI" (Ollama, 7B max); read `/mnt/recoverybuild/CLAUDE.md`.
- **I30LTZ Companion**: Android app that manages every node (SWARM OS, CachyOS, Debian, Recovery OS); source `/mnt/boltzbuild/src/I30LTZ-Recovery-companion/` (the **Boltz Recovery** phone app on build partition D; moved there 2026-10-09; decided 2026-10-07; `30-source/companion-app/` is superseded). Node agent: `30-source/i30ltz-node/`. Build: `JAVA_HOME=~/.jdks/jdk-21 ./gradlew :app:assembleDebug`. Tracker rows CP-01..CP-16.
- **Lucille Assistant**: Android phone app for SWARM; source `/mnt/Lucy/lucille-companion/`.
