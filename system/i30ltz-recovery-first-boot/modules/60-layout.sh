# shellcheck shell=bash
# about: organized, numbered home folders — each OS project kept separate
# I30LTZ Recovery OS first boot v2.1.0 · 2026-10-01

[[ -n "$TARGET_HOME" ]] || { info "no --user given — home layout skipped"; return 0; }

base="$TARGET_HOME/SWARM_OS"
dirs=(
  "00-inbox"                    # drop zone — sort later
  "10-releases"                 # ISOs, builds, dated + versioned
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
# SWARM_OS Suite — home layout on I30LTZ Recovery OS
v2.1.0 · 2026-10-01 · created by the I30LTZ Recovery OS first-boot kit

Recovery OS repairs this PC **and** builds SWARM_OS for the internal NVMe.
Keep the two projects apart: **SWARM_OS** (LLcy) in 40-, **I30LTZ** (MAD IT) in 50-.
Build SWARM_OS from 30-source/swarm-os with \`swarm-build\`, test with \`swarm-test-iso\`.

| Folder | What goes here |
|---|---|
| 00-inbox | anything new; sort weekly |
| 10-releases | builds and ISOs, name them \`thing_vX.Y.Z_YYYY-MM-DD\` |
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
