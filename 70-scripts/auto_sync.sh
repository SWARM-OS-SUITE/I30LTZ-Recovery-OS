#!/bin/bash
# Auto-sync the two Recovery OS repos to GitHub while working on them.
#   /mnt/recoverybuild               -> cledford955-maker/I30LTZ-Recovery-OS
#   /mnt/boltzbuild/src/I30LTZ-Recovery-companion -> cledford955-maker/I30LTZ-Recovery-companion   (moved from recoverybuild 2026-10-09)
# No-ops when nothing changed. Never force-pushes. On divergence it stops and reports.
set -uo pipefail
MAX_MB=90   # GitHub rejects files >100MB
status=0

sync_repo() {
  local dir=$1
  [ -d "$dir/.git" ] || { echo "SKIP: $dir not a git repo (drive not mounted?)"; return; }
  cd "$dir" || return
  if [ "$(git branch --show-current)" != main ]; then echo "PAUSED $dir: not on main" >&2; status=1; return; fi
  for op in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [ -e "$(git rev-parse --git-path $op)" ] && { echo "PAUSED $dir: git operation in progress" >&2; status=1; return; }
  done
  if ! git diff --cached --quiet; then echo "PAUSED $dir: staged changes belong to someone else" >&2; status=1; return; fi
  git add -A
  big=$(git diff --cached --name-only -z | xargs -0 -r -I{} find {} -maxdepth 0 -size +${MAX_MB}M 2>/dev/null)
  if [ -n "$big" ]; then
    git reset -q; echo "ERROR $dir: files over ${MAX_MB}MB, not committing:" >&2; echo "$big" >&2; status=1; return
  fi
  if ! git diff --cached --quiet; then
    git commit -q -m "auto-sync: $(date -Iseconds)" || { echo "ERROR $dir: commit failed" >&2; status=1; return; }
  fi
  git fetch -q origin || { echo "ERROR $dir: fetch failed" >&2; status=1; return; }
  if ! git merge-base --is-ancestor origin/main HEAD; then
    if git merge-base --is-ancestor HEAD origin/main; then git merge -q --ff-only origin/main
    else echo "CONFLICT $dir: local and GitHub diverged; resolve by hand" >&2; status=1; return; fi
  fi
  if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    git push -q origin main && echo "SYNC OK: $dir" || { echo "ERROR $dir: push failed" >&2; status=1; }
  else
    echo "up to date: $dir"
  fi
}

mountpoint -q /mnt/recoverybuild || { echo "SKIP: /mnt/recoverybuild not mounted"; exit 0; }
exec 9>/tmp/recoverybuild-sync.lock; flock -n 9 || { echo "already running"; exit 0; }
# Companion first so the OS repo (which ignores it) is unaffected either way.
sync_repo /mnt/boltzbuild/src/I30LTZ-Recovery-companion
sync_repo /mnt/recoverybuild
exit $status
