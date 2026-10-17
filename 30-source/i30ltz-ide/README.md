# I30LTZ IDE (RC-14)

The professional IDE of **I30LTZ Recovery OS**, for coding on a rescued machine. Flutter / Linux desktop, fully offline.
AI pair programmer: **Dr. I30LTZ "MAD AI"** (local Ollama on 127.0.0.1:11434 only; 7B max; it proposes, you click Copy; nothing is run or applied for you).

## Provenance (fork, so later Apex changes do not flow in)
Forked 2026-10-12 from SWARM OS **Apex** (`/mnt/Lucy/30-source/frontend/lib/agent/apex_workstation.dart` + `lib/coder`, SWARM
git 0e27a2a). Only the 50 files Apex needs were taken. SWARM-specific parts were cut or replaced: the Apex/Lucille agent chat,
Sentinel/LucyServer clients, auth token config, telemetry, RAG tab, GitLens/Diff studio routes, go_router, Google Fonts
(runtime download) and the OpenRouter / Google Antigravity extensions hub. Branding, colours and AI are I30LTZ's own.

## Build (normal user, never root)
`bash 70-scripts/build-ide.sh`  -> `build/linux/x64/release/bundle/` (28 MB). SDK + pub cache live on this partition in
`25-toolchain/` (git-ignored). `70-scripts/build.sh` copies the bundle into the ISO at `/opt/i30ltz/ide`; launcher `i30ltz-ide`.

## Panel status (verified = analyzer clean + release build + window launched + MAD AI panel reached Ollama; not tested on a rescue PC)
| Panel | Status |
|---|---|
| Editor (tabs, syntax highlight, folding, split, intellisense), Explorer, Search, Snippets, Keybindings, Accessibility | in the build, launches |
| Git panel, Terminal (PTY via `script`), Problems/Output | in the build; need `git` (added to the ISO package list) |
| MAD AI chat | rewritten: local Ollama, streaming (NDJSON reply format checked with curl against gemma3:1b), model picker, Copy buttons. The in-app streamed reply itself was not clicked through. |
| Ollama panel | in the build; installed models + pull catalog (all <=7B; the 8B entries were removed); delete asks to confirm |
| Device files / Task runner | in the build; Device files is Android-device oriented (adb) and mostly useless on a rescue PC; not removed |
| Android, Apple, Signing, Publisher portal, Controller (gamepad) | REMOVED 2026-10-12 at the user's request, with their services, the extension publish dialog's entry and the radial menu / virtual keyboard |
| Hot reload button | Flutter dev feature; needs a Flutter SDK on the machine |

## Known gaps
Not tested inside the ISO (needs a build + boot). `~/.i30ltz-ide/` holds settings and workspace state. No tests yet.
