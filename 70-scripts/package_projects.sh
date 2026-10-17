#!/usr/bin/env bash
# Builds the 4 deliverable zips on the Desktop: SWARM-OS, Recovery-OS, Lucille-Assistant, Mad-Dr-Boltz.
# Excludes build output, venvs, SDKs, secrets, ISOs. Originals are never modified.
set -euo pipefail
OUT="${1:-$HOME/Desktop}"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
z() { zip "$@" || [ $? -eq 18 ]; }  # 18 = some files unreadable (root-owned); not fatal
COMMON=(-x '*/target/*' '*/build/*' '*/.gradle/*' '*/node_modules/*' '*/venv/*' '*/.venv/*' '*/.dart_tool/*'
        '*/__pycache__/*' '*/.git/*' '*/.env' '*/.env.*' '*.iso' '*.apk' '*.aab' '*.o' '*.so')

mountpoint -q /mnt/Lucy && mountpoint -q /mnt/recoverybuild || { echo "mounts missing" >&2; exit 1; }

# 1. SWARM OS (everything except the Lucille Assistant app, SDKs, secrets, archives)
cd /mnt/Lucy
rm -f "$OUT/SWARM-OS.zip"
z -rq "$OUT/SWARM-OS.zip" CLAUDE.md SWARM_AI_FEATURES.md ISO_RELEASE_POLICY.md README.md VERSION 30-source 40-iso-profile 70-scripts 90-docs images lucille-companion \
  "${COMMON[@]}" '30-source/flutter-sdk/*' '30-source/LucilleAssistant/*' '30-source/swarm-overlay/*' '*/airootfs/opt/*' '*/airootfs/usr/*'

# 2. Lucille Assistant app
cd /mnt/Lucy/30-source
rm -f "$OUT/Lucille-Assistant.zip"
z -rq "$OUT/Lucille-Assistant.zip" LucilleAssistant "${COMMON[@]}"

# 3. Recovery OS (Mad Dr Boltz, incl. the Android companion, ships separately)
cd /mnt/recoverybuild
rm -f "$OUT/Recovery-OS.zip"
z -rq "$OUT/Recovery-OS.zip" . "${COMMON[@]}" 'swapfile' '20-runtime/*' '40-iso-profile/chroot/*' '40-iso-profile/cache/*' '10-releases/*' '99-archive/*' '30-source/mad-dr-ai/*' '30-source/mad-dr-boltz/*' '30-source/companion-app/*'

# 4. Mad Dr Boltz = mad-dr-boltz (brain + SOUL) + mad-dr-ai (SSE bridge) + the Android companion (on /mnt/boltzbuild) as one app
mkdir -p "$STAGE/Mad-Dr-Boltz"
cp -a /mnt/recoverybuild/30-source/mad-dr-boltz/. "$STAGE/Mad-Dr-Boltz/"
cp -a /mnt/recoverybuild/30-source/mad-dr-ai/sse-server "$STAGE/Mad-Dr-Boltz/sse-server"
# The Android app lives on build partition D. `git archive` takes TRACKED files only, so the gitignored
# debug.keystore (the signing key) can never end up in a zip.
if mountpoint -q /mnt/boltzbuild && [ -d /mnt/boltzbuild/src/I30LTZ-Recovery-companion/.git ]; then
  mkdir -p "$STAGE/Mad-Dr-Boltz/android-companion"
  git -C /mnt/boltzbuild/src/I30LTZ-Recovery-companion archive HEAD | tar -x -C "$STAGE/Mad-Dr-Boltz/android-companion"
else
  echo "WARN: /mnt/boltzbuild not mounted: Mad-Dr-Boltz.zip is built WITHOUT the Android app" >&2
fi
cat > "$STAGE/Mad-Dr-Boltz/README.md" <<'EOT'
# Mad Dr Boltz
One app, three parts (previously mad-dr-boltz + mad-dr-ai + companion-app):
- `brain/`      boltz_server.py — Dr. I30LTZ brain (Ollama, 7B max), identity in `SOUL.md`
- `sse-server/` sse_bridge.py — SSE bridge to the Android companion
- `android-companion/` Android app (I30LTZ Companion, com.aistudio.sysopt.app; source only, no signing key)
Used by Recovery OS and SWARM OS. Create a venv from each requirements.txt to run.
EOT
cd "$STAGE"; rm -f "$OUT/Mad-Dr-Boltz.zip"
z -rq "$OUT/Mad-Dr-Boltz.zip" Mad-Dr-Boltz "${COMMON[@]}"
ls -lh "$OUT"/{SWARM-OS,Recovery-OS,Lucille-Assistant,Mad-Dr-Boltz}.zip
