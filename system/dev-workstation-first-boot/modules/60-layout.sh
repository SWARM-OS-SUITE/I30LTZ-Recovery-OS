# shellcheck shell=bash
# about: organized, numbered home folders — each OS project kept separate
# SWARM_OS Suite dev workstation v2.0.0 · 2026-09-30

base="$TARGET_HOME/SWARM_OS"
dirs=(
  "00-inbox"                    # drop zone — sort later
  "10-releases"                 # ISOs, builds, dated + versioned
  "20-games"                    # saves, mods, MangoHud configs
  "30-source"                   # git repos: swarm-os + i30ltz-recovery, side by side, never mixed
  "40-lucille-llcy"             # SWARM_OS project: LLcy notes, prompts, memory exports
  "50-i30ltz-cases"             # I30LTZ Recovery OS project: MAD IT notes + test cases
  "60-assets/visuals"           # wallpapers, icons, 8K renders
  "70-scripts"                  # your helper scripts
  "80-backups"                  # snapshots + exported configs
  "90-archive"                  # finished things
)
for d in "${dirs[@]}"; do
  run install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$base/$d"
done

write_file "$base/README.md" 0644 <<EOM
# SWARM_OS Suite — dev workstation home layout
v2.0.0 · 2026-09-30 · created by the dev-workstation first-boot kit

This laptop builds two separate operating systems. Keep their work apart:
**SWARM_OS** (LLcy) in 40-, **I30LTZ Recovery OS** (MAD IT) in 50-.

| Folder | What goes here |
|---|---|
| 00-inbox | anything new; sort weekly |
| 10-releases | builds and ISOs, name them \`thing_vX.Y.Z_YYYY-MM-DD\` |
| 20-games | saves, mods, overlays |
| 30-source | git repos, one folder per OS |
| 40-lucille-llcy | SWARM_OS · LLcy prompts, notes, memory |
| 50-i30ltz-cases | I30LTZ Recovery OS · MAD IT notes (evidence stays in /var/lib/i30ltz/cases) |
| 60-assets | visuals, icons, renders |
| 70-scripts | your scripts |
| 80-backups | exports + snapshots |
| 90-archive | done and dusted |
EOM
[[ "$DRY_RUN" == 1 ]] || chown "$TARGET_USER:$TARGET_USER" "$base/README.md"
ok "home layout: $base"
