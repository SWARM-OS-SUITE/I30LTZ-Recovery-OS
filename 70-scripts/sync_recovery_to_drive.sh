#!/usr/bin/env bash
# Syncs the Recovery OS projects to Google Drive (shared with ironsight.13roken@gmail.com).
# Run by ~/.config/systemd/user/recovery-drive-sync.timer (6x/day).
set -euo pipefail
SRC=/mnt/recoverybuild/30-source
DEST="Swarm os suite:Recovery-OS"
mountpoint -q /mnt/recoverybuild || { echo "recoverybuild not mounted" >&2; exit 1; }
for p in i30ltz-recovery mad-dr-ai mad-dr-boltz; do   # companion-app removed 2026-10-09 (the Android app lives on /mnt/boltzbuild)
  rclone sync "$SRC/$p" "$DEST/$p" \
    --exclude 'target/**' --exclude '.env' --exclude '.env.*' --exclude '.git/**' \
    --drive-acknowledge-abuse -v
done
