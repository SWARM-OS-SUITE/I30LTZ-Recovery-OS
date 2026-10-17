#!/usr/bin/env bash
# Shared "who is working where" board for every AI (Claude, Codex, Gemini, ...) on every project.
# Data file: /mnt/recoverybuild/00-CURRENT/ai-board.tsv  (append-only, plain text, no secrets)
#   ai-board.sh list
#   ai-board.sh claim <ai-name> <area> "<task>"   (area = path or project code, e.g. /mnt/Lucy/30-source/frontend, RC, SW-01)
#   ai-board.sh done  <ai-name> <area> ["<note>"]
#   ai-board.sh idea  <ai-name> "<idea or add-on>"   (appends to the Idea inbox in MASTER_BUILD_LIST.md)
set -euo pipefail
ROOT="${AI_BOARD_ROOT:-/mnt/recoverybuild/00-CURRENT}"
TSV="$ROOT/ai-board.tsv"; MASTER="$ROOT/MASTER_BUILD_LIST.md"
[ -d "$ROOT" ] || { echo "board root missing: $ROOT (is /mnt/recoverybuild mounted?)" >&2; exit 2; }
touch "$TSV"; now() { date -Is; }
state() { # ACTIVE claims only: last event per (ai,area) wins
  awk -F'\t' '{k=$2"\t"$3; ev[k]=$4; ts[k]=$1; task[k]=$5} END{for(k in ev) if(ev[k]=="CLAIM") print ts[k]"\t"k"\t"task[k]}' "$TSV" | sort
}
case "${1:-list}" in
  list)  printf 'ACTIVE CLAIMS (since / AI / area / task)\n'; state | column -t -s$'\t' || true
         n=$(state | wc -l); [ "$n" = 0 ] && echo "(none)";;
  claim) ai="${2:?ai}"; area="${3:?area}"; task="${4:-}"
         clash="$(state | awk -F'\t' -v ai="$ai" -v a="$area" '$2!=ai && (index($3,a)==1 || index(a,$3)==1) {print "  "$2" has "$3" ("$4")"}')"
         if [ -n "$clash" ]; then echo "OVERLAP: another AI already claims a related area:"; echo "$clash"; echo "Coordinate first (ask the user). Claim NOT recorded."; exit 1; fi
         printf '%s\t%s\t%s\tCLAIM\t%s\n' "$(now)" "$ai" "$area" "$task" >> "$TSV"; echo "claimed $area for $ai";;
  done)  ai="${2:?ai}"; area="${3:?area}"
         printf '%s\t%s\t%s\tDONE\t%s\n' "$(now)" "$ai" "$area" "${4:-}" >> "$TSV"; echo "released $area for $ai";;
  idea)  ai="${2:?ai}"; idea="${3:?idea}"
         printf -- '- %s %s: %s\n' "$(date +%F)" "$ai" "$idea" > /tmp/.idea.$$
         python3 - "$MASTER" /tmp/.idea.$$ <<'PY'
import sys
p, f = sys.argv[1], sys.argv[2]
s = open(p).read(); line = open(f).read()
mark = "\n## Retired by this file"
i = s.index(mark)
open(p, "w").write(s[:i].rstrip("\n") + "\n" + line + s[i:])
PY
         rm -f /tmp/.idea.$$; echo "idea added to MASTER_BUILD_LIST.md";;
  *) sed -n 2,8p "$0"; exit 1;;
esac
