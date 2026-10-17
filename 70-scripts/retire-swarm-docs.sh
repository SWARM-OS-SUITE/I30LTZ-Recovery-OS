#!/usr/bin/env bash
# Retire the SWARM docs already consolidated into MASTER_BUILD_LIST.md (see 00-CURRENT/CONSOLIDATION_LOG.md).
# Run by the user or the SWARM AI, NOT by the Recovery AI. Uses `git rm`, so every file stays recoverable.
# Refuses any file that is untracked or differs from HEAD.
set -euo pipefail
cd /mnt/Lucy
FILES=(
 SWARM_AI_FEATURES.md.bak-2026-09-19
 SWARM_OS_IMPLEMENTATION_CHECKLIST.md.bak-2026-09-19
 SWARM_OS_DAILY_AUDIT_2026-09-24_v1.0.0.md
 90-docs/remaining_port_tasks.md
 90-docs/SWARM_OS_DAILY_AUDIT_2026-09-16_v1.0.0.md
 90-docs/SWARM_OS_DAILY_AUDIT_2026-09-17_v1.0.0.md
 90-docs/SWARM_OS_DAILY_AUDIT_2026-09-18_v1.0.0.md
 90-docs/SWARM_OS_DAILY_AUDIT_2026-09-20_v1.0.0.md
 90-docs/SWARM_OS_DAILY_AUDIT_2026-09-23_v1.0.0.md
 90-docs/SWARM_OS_DAILY_AUDIT_2026-09-23_v1.1.0.md
 90-docs/SWARM_OS_DAILY_AUDIT_2026-09-28_v1.0.0.md
)
for f in "${FILES[@]}"; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 || { echo "skip (untracked): $f"; continue; }
  git diff --quiet HEAD -- "$f" || { echo "skip (modified since HEAD): $f"; continue; }
  git rm -q -- "$f" && echo "retired: $f"
done
echo "Now commit in /mnt/Lucy. Restore any file with: git checkout HEAD~1 -- <path>"
