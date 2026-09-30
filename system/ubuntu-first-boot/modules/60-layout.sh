# shellcheck shell=bash
# about: organized, numbered home folders for SWARM_OS + I30LTZ work
# SWARM_OS Suite · Ubuntu First Boot v1.0.0 · 2026-09-30

base="$TARGET_HOME/SWARM_OS"
dirs=(
  "00-inbox"                    # drop zone — sort later
  "10-releases"                 # ISOs, builds, dated + versioned
  "20-games"                    # saves, mods, MangoHud configs
  "30-source"                   # git repos (i30ltz-recovery lives here)
  "40-lucille-llcy"             # LLcy notes, prompts, memory exports
  "50-i30ltz-cases"             # your own recovery notes (evidence stays in /var/lib/i30ltz)
  "60-assets/visuals"           # wallpapers, icons, 8K renders
  "70-scripts"                  # your helper scripts
  "80-backups"                  # snapshots + exported configs
  "90-archive"                  # finished things
)
for d in "${dirs[@]}"; do
  wants swarm || [[ "$d" != 20-games && "$d" != 40-lucille-llcy ]] || continue
  wants recovery || [[ "$d" != 50-i30ltz-cases ]] || continue
  run install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$base/$d"
done

write_file "$base/README.md" 0644 <<EOM
# SWARM_OS — home layout
v1.0.0 · 2026-09-30 · created by Ubuntu First Boot kit

| Folder | What goes here |
|---|---|
| 00-inbox | anything new; sort weekly |
| 10-releases | builds and ISOs, name them \`thing_vX.Y.Z_YYYY-MM-DD\` |
| 20-games | saves, mods, overlays |
| 30-source | git repos |
| 40-lucille-llcy | LLcy prompts, notes, memory |
| 50-i30ltz-cases | Dr. I30LTZ case notes (evidence stays in /var/lib/i30ltz/cases) |
| 60-assets | visuals, icons, renders |
| 70-scripts | your scripts |
| 80-backups | exports + snapshots |
| 90-archive | done and dusted |
EOM
[[ "$DRY_RUN" == 1 ]] || chown "$TARGET_USER:$TARGET_USER" "$base/README.md"
ok "home layout: $base"
