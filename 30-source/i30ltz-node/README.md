# i30ltz-node

The small agent that runs on **each machine** (SWARM OS, CachyOS, Debian, Recovery OS) so the
I30LTZ Companion app can see and control it. One static Go binary, standard library only.

## Build and test
```bash
cd /mnt/recoverybuild/30-source/i30ltz-node
go vet ./... && go test -race ./...
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dist/i30ltz-node .
```

## Run and pair
```bash
./dist/i30ltz-node serve              # listens on tailscale0 and 127.0.0.1, port 7437
./dist/i30ltz-node pair               # prints a one-time code (valid 10 min); run on THIS machine
./dist/i30ltz-node devices            # paired phones
./dist/i30ltz-node revoke "my phone"  # takes effect immediately
```
In the app: Monitor -> Nodes -> Add node -> *I30LTZ node agent* -> host, port 7437, pairing code -> PAIR -> TEST -> SAVE.

## Mirrored terminal (`--terminal`)
Off by default. With `serve --terminal`, a paired phone can attach to a **tmux** session on this machine. The phone and the
machine are then two tmux clients of the same session: what you type on either shows on both.
```bash
./dist/i30ltz-node serve --terminal    # needs tmux installed
./dist/i30ltz-node shell               # on THIS machine: join the shared session (default name "main")
./dist/i30ltz-node shell work          # or another session name; pick it in the app
```
To make your everyday terminal mirrorable, set its start command (Konsole profile, `~/.bashrc`: `exec i30ltz-node shell`) to `i30ltz-node shell`.
Leaving from the phone does **not** end the session; `tmux` keeps it running.
By default the tmux window is as small as the smallest attached client (`--window-size smallest`), so the phone and the PC see exactly the same lines; the PC view narrows only while the phone is attached. `--window-size latest` keeps the PC at full size, but then the phone sees only a slice of the window whenever the PC typed last.

## Malware scanning (ClamAV)
The agent drives **ClamAV** (`clamscan`); install it on the node (`apt install clamav` / `pacman -S clamav`) and keep its
signatures current (`freshclam`, normally automatic). The app shows the signature age and warns after 7 days.
```bash
./dist/i30ltz-node serve --clamscan /path/to/clamscan --clam-db /path/to/signatures   # both optional
```
- **Scopes:** `quick` (Downloads, /tmp, /var/tmp, ~/.local/bin, ~/bin, /usr/local/bin, autostart), `home`, `full` (/ without
  /proc /sys /dev /run and without other mounted drives), or `path` (any absolute folder or file, e.g. a USB drive).
- **Scanning only reports.** Nothing is deleted, moved or changed until a paired phone explicitly asks to *quarantine* a finding.
  Quarantine re-scans the file first (a clean file that replaced the infected one is never touched), copies it into a private
  folder with its SHA-256, and only then removes the original; if that fails nothing changes. It is reversible (*restore* never
  overwrites) and only files that were findings of that scan can be quarantined.
- **No false all-clear:** a broken or empty signature database is a *failed* scan; files that cannot be read (`Access denied`) and
  results the agent does not recognise are counted as errors, never as clean. Symlinks are not followed.
- Runs at the lowest CPU priority, one scan at a time, as the user the agent runs as: **run it as root (or give it read access) if you
  want system files checked**; a normal user only covers what that user can read.

## API v1 (`Authorization: Bearer <token>` except pairing)
| | |
|---|---|
| `POST /v1/pair` | `{"code","label"}` -> `{"token"}`; 5 wrong codes lock pairing for 60 s |
| `GET /v1/pairing/new` | makes a code; **loopback only** |
| `GET /v1/capabilities` | what this node really supports (`optimize/jobs` are `false` until built; `scan` is true when ClamAV is installed) |
| `GET /v1/telemetry`, `GET /v1/events` | snapshot, or SSE every 2 s (`event: telemetry`) |
| `GET /v1/terminal/sessions` | tmux sessions (`--terminal` only) |
| `GET /v1/terminal?session=NAME&cols=N&rows=M` | WebSocket (`--terminal` only). Binary messages = terminal bytes both ways; text `{"type":"resize","cols":N,"rows":M}` |
| `GET /v1/scan` | scanner status (engine, signature version/age, `signatures_stale`) and recent scans |
| `POST /v1/scan` | `{"scope":"quick\|home\|full\|path","path":"/abs"}` -> `202 {"id"}`; `409` if one is running, `501` if no scanner |
| `GET /v1/scan/{id}`, `POST /v1/scan/{id}/cancel` | progress (`scanned_files`, `current`, `errors`) and `findings` |
| `POST /v1/scan/{id}/quarantine` | `{"path"}`, must be a finding of that scan |
| `GET /v1/quarantine`, `POST /v1/quarantine/{id}/restore`, `DELETE /v1/quarantine/{id}` | list, put back, delete for good |
| `GET /v1/processes?limit=N`, `POST /v1/processes/{pid}/kill[?force=1]` | refuses pid 1, itself, kernel threads |

Unmeasurable values are `-1` (or absent), never a made-up number.

## Security notes
- Only SHA-256 hashes of tokens are stored (`paired.json`, mode 0600, directory 0700). Nothing secret is logged.
- Default listen addresses are Tailscale + loopback. **The traffic is plain HTTP**: safe over Tailscale (WireGuard),
  not safe on a shared LAN, USB tether or Bluetooth link until TLS is added (CP-08).
- **`--terminal` gives every paired phone a shell as the user the agent runs as** (like an SSH key). Pair only phones you
  own, `revoke` lost ones, and do not run the agent as root unless you mean to hand out a root shell. The log records who
  attached to which session and for how long, never what was typed.
- Whoever holds a token can stop any process the agent's user may signal. Run it as a normal user unless
  you want that to include root's processes.
- A ready-made user service is in `contrib/i30ltz-node.service` (not installed by anything).
- Not yet: ISO packaging, optimize, jobs (see `MASTER_BUILD_LIST.md` CP-08..CP-13).
