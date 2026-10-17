#!/usr/bin/env bash
# Verify that the canonical mount points (mounts.manifest) match reality, and that
# /etc/fstab follows the rules. Read-only, needs no root. Exit 0 = all good, 1 = problems.
#   check-mounts.sh           human-readable report
#   check-mounts.sh --quiet   print only problems (for timers)
# Runs on every OS; the same manifest applies everywhere.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${MOUNTS_MANIFEST:-$HERE/mounts.manifest}"
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1
bad=0
say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*"; bad=1; }

[ -r "$MANIFEST" ] || { echo "manifest not found: $MANIFEST" >&2; exit 2; }

# uuid -> "fstype|mountpoint" for every block device lsblk can see (includes unlocked LUKS inner fs)
declare -A FS MP
while IFS= read -r line; do
  eval "$line"            # lsblk -P gives KEY="value" pairs (shell-safe)
  [ -n "${UUID:-}" ] || continue
  FS["$UUID"]="$FSTYPE"
  # first mountpoint only; lsblk -P escapes spaces as \x20
  MP["$UUID"]="$(printf '%b' "${MOUNTPOINT:-}")"
done < <(lsblk -P -n -o UUID,FSTYPE,MOUNTPOINT 2>/dev/null)

say "== canonical mounts ($(hostname), $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-?}"))"
while IFS=$'\t' read -r mp uuid fstype label owner req _; do
  case "$mp" in ''|\#*) continue;; esac
  if [ -z "${FS[$uuid]+x}" ]; then
    say "  ABSENT    $mp  ($label, $uuid): drive not attached or LUKS locked"
    continue
  fi
  actual="${MP[$uuid]}"
  # lsblk names one mountpoint per device; a device ALSO mounted at the canonical path (e.g. C at
  # /mnt/lucillebuild plus a bind kept at /mnt/lucilleassistant for old paths, 2026-10-16) is OK.
  if [ -n "$actual" ] && [ "$actual" != "$mp" ]; then
    here="$(findmnt -rn -M "$mp" -o SOURCE 2>/dev/null | head -n1)"
    [ -n "$here" ] && [ "$(readlink -f "$here")" = "$(readlink -f "/dev/disk/by-uuid/$uuid")" ] && actual="$mp"
  fi
  holder="$(findmnt -n -o SOURCE --target "$mp" 2>/dev/null)"
  if [ "$actual" = "$mp" ]; then
    say "  OK        $mp  ($label)"
  elif [ -z "$actual" ] && findmnt -n -t autofs "$mp" >/dev/null 2>&1; then
    say "  OK        $mp  ($label, automount idle)"
  elif [ -n "$actual" ]; then
    warn "  WRONGPATH $mp  ($label) is mounted at $actual; must be $mp on every OS"
  else
    warn "  UNMOUNTED $mp  ($label, $uuid) is attached but not mounted"
  fi
  if [ "$actual" != "$mp" ] && mountpoint -q "$mp" 2>/dev/null; then
    warn "  CONFLICT  $mp is in use by $holder, not the expected UUID $uuid"
  fi
done < "$MANIFEST"

# fstab hygiene (only when this OS has a readable fstab)
if [ -r /etc/fstab ]; then
  say "== /etc/fstab"
  awk '!/^[[:space:]]*(#|$)/ {print NR": "$0}' /etc/fstab | while IFS= read -r l; do
    n="${l%%:*}"; f="$(sed -n "${n}p" /etc/fstab)"
    set -- $f
    case "${2:-}" in /mnt/*) ;; *) continue;; esac
    [ $# -lt 4 ] && echo "  MALFORMED line $n ($f): needs 6 fields" && continue
    case "$1" in /dev/sd*|/dev/nvme*|/dev/disk/by-id/*|/dev/disk/by-path/*) echo "  UNSTABLE  line $n: $1 (use UUID=)";; esac
    case "$4" in *nofail*) ;; *) echo "  NOFAIL    line $n: $2 lacks nofail (a missing drive could block boot)";; esac
  done | { out="$(cat)"; [ -n "$out" ] && { printf '%s\n' "$out"; exit 3; } || true; }
  [ "${PIPESTATUS[1]:-0}" = 3 ] && bad=1
  dups="$(awk '!/^[[:space:]]*(#|$)/ && $2 ~ /^\/mnt\// {print $2}' /etc/fstab | sort | uniq -d)"
  [ -n "$dups" ] && { warn "  DUPLICATE mountpoints in fstab: $(echo $dups)"; }
  for u in $(grep -o '^UUID=[^[:space:]]*' /etc/fstab | cut -d= -f2); do
    [ -e "/dev/disk/by-uuid/$u" ] || say "  note: fstab UUID $u not present right now (ok if that drive is detached)"
  done
fi

[ "$bad" = 0 ] && say "ALL OK" || echo "PROBLEMS FOUND: fix them, then re-run $0"
exit "$bad"
