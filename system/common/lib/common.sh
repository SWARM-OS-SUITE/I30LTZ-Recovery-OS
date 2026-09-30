# shellcheck shell=bash disable=SC2034
# =============================================================================
# Ubuntu first boot · shared helpers
# Version: 2.0.0 | Date: 2026-09-30
# Sourced by common/runner.sh and every module. Never run directly.
# =============================================================================

C_RED=$'\033[0;31m'; C_CYAN=$'\033[0;36m'; C_AMBER=$'\033[0;33m'
C_GREEN=$'\033[0;32m'; C_MAG=$'\033[0;35m'; C_BOLD=$'\033[1m'; C_NC=$'\033[0m'

LOG_DIR="${LOG_DIR:-/var/log/first-boot}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/first-boot}"
DRY_RUN="${DRY_RUN:-0}"

_stamp() { date '+%Y-%m-%d %H:%M:%S'; }
_log()   { printf '%s %s\n' "$(_stamp)" "$*" >>"${LOG_FILE:-/dev/null}" 2>/dev/null || true; }

info() { printf '%s[ INFO ]%s %s\n' "$C_CYAN"  "$C_NC" "$*"; _log "INFO  $*"; }
ok()   { printf '%s[  OK  ]%s %s\n' "$C_GREEN" "$C_NC" "$*"; _log "OK    $*"; }
warn() { printf '%s[ WARN ]%s %s\n' "$C_AMBER" "$C_NC" "$*"; _log "WARN  $*"; WARNINGS+=("$*"); }
die()  { printf '%s[ FAIL ]%s %s\n' "$C_RED"   "$C_NC" "$*" >&2; _log "FAIL  $*"; exit 1; }
step() { printf '\n%s%s━━ %s ━━%s\n' "$C_MAG" "$C_BOLD" "$*" "$C_NC"; _log "STEP  $*"; }

WARNINGS=()

# run CMD... — executes (or prints in dry-run) and logs the command.
run() {
  _log "RUN   $*"
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  [dry]%s %s\n' "$C_AMBER" "$C_NC" "$*"
    return 0
  fi
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

# Package is known to apt (any enabled component)?
pkg_available() { apt-cache show "$1" >/dev/null 2>&1; }
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

# apt_install PKG... — install required packages (fails loudly).
apt_install() {
  local todo=() p
  for p in "$@"; do pkg_installed "$p" || todo+=("$p"); done
  ((${#todo[@]})) || { ok "already installed: $*"; return 0; }
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${todo[@]}"
}

# apt_optional PKG... — install what exists, skip + warn on the rest.
apt_optional() {
  local have_pkgs=() missing=() p
  for p in "$@"; do
    if pkg_installed "$p"; then continue
    elif pkg_available "$p"; then have_pkgs+=("$p")
    else missing+=("$p"); fi
  done
  ((${#missing[@]})) && warn "not in this Ubuntu's repos, skipped: ${missing[*]}"
  ((${#have_pkgs[@]})) || return 0
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${have_pkgs[@]}" \
    || warn "optional install had errors: ${have_pkgs[*]}"
}

# backup_file PATH — timestamped copy before we change a system file.
backup_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  run mkdir -p "$BACKUP_DIR"
  # full path in the name, so /etc/a/release and /etc/b/release never collide
  local name="${f#/}"; name="${name//\//__}"
  run cp -a "$f" "$BACKUP_DIR/${name}.$(date +%Y%m%d-%H%M%S).bak"
}

# write_file PATH MODE < content — backs up, then writes atomically.
write_file() {
  local dest="$1" mode="${2:-0644}" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"; ok "unchanged: $dest"; return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  [dry]%s write %s (%s lines)\n' "$C_AMBER" "$C_NC" "$dest" "$(wc -l <"$tmp")"
    rm -f "$tmp"; return 0
  fi
  backup_file "$dest"
  mkdir -p "$(dirname "$dest")"
  install -m "$mode" "$tmp" "$dest"
  rm -f "$tmp"
  ok "wrote: $dest"
}

enable_component() {  # universe / multiverse / restricted
  local c="$1"
  if grep -rqsE "^(Components:.*\b$c\b|deb .*\b$c\b)" /etc/apt/sources.list /etc/apt/sources.list.d/; then
    ok "apt component already enabled: $c"
  else
    run add-apt-repository -y -n "$c"
    APT_DIRTY=1
  fi
}
