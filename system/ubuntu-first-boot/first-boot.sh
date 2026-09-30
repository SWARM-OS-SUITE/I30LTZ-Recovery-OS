#!/usr/bin/env bash
# =============================================================================
# SWARM_OS Suite — Ubuntu First Boot (secure setup)
# Version: 1.0.0 | Date: 2026-09-30
#
# Profiles:
#   swarm     SWARM_OS · LUCILLE CORE AI "LLcy"  — daily life, gaming, coding
#   recovery  I30LTZ Recovery OS · Dr. I30LTZ "MAD IT" — PC repair, data recovery
#   both      everything (default)
#
# Safe to re-run. Every changed system file is backed up first.
#   sudo ./first-boot.sh --dry-run           # preview, changes nothing
#   sudo ./first-boot.sh                     # full run, profile "both"
#   sudo ./first-boot.sh --profile swarm
#   sudo ./first-boot.sh --only 20-harden
# =============================================================================
set -Eeuo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$KIT_DIR/../.." && pwd)"
# shellcheck source=lib/common.sh
source "$KIT_DIR/lib/common.sh"

PROFILE="both"
ONLY=""
SKIP=""
ENABLE_SSH=0
ASSUME_YES=0
TARGET_USER="${SUDO_USER:-}"

usage() {
  cat <<EOF
SWARM_OS Suite · Ubuntu First Boot v${KIT_VERSION} (${KIT_DATE})

Usage: sudo $0 [options]
  --profile swarm|recovery|both   what to set up (default: both)
  --user NAME                     owner of the organized home folders (default: \$SUDO_USER)
  --only  MOD[,MOD]               run only these modules (e.g. 20-harden)
  --skip  MOD[,MOD]               skip these modules
  --enable-ssh                    install + harden OpenSSH (off by default = safer)
  --dry-run                       show what would happen, change nothing
  -y, --yes                       don't ask for confirmation
  -h, --help                      this help

Modules:
EOF
  for m in "$KIT_DIR"/modules/*.sh; do
    printf '  %-22s %s\n' "$(basename "$m" .sh)" "$(sed -n 's/^# about: //p' "$m")"
  done
}

while (($#)); do
  case "$1" in
    --profile)    PROFILE="${2:?}"; shift 2 ;;
    --user)       TARGET_USER="${2:?}"; shift 2 ;;
    --only)       ONLY="${2:?}"; shift 2 ;;
    --skip)       SKIP="${2:?}"; shift 2 ;;
    --enable-ssh) ENABLE_SSH=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -y|--yes)     ASSUME_YES=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) usage; die "unknown option: $1" ;;
  esac
done

case "$PROFILE" in swarm|recovery|both) ;; *) die "--profile must be swarm, recovery or both" ;; esac
[[ $EUID -eq 0 ]] || die "run as root:  sudo $0 $*"
[[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || die "tell me whose home to organize:  --user YOURNAME"
id "$TARGET_USER" >/dev/null 2>&1 || die "user not found: $TARGET_USER"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

export PROFILE ENABLE_SSH DRY_RUN TARGET_USER TARGET_HOME KIT_DIR REPO_DIR
APT_DIRTY=0

wants() {  # wants swarm|recovery
  [[ "$PROFILE" == both || "$PROFILE" == "$1" ]]
}

in_list() { [[ ",$2," == *",$1,"* ]]; }

RUN_ID="$(date +%Y-%m-%d_%H%M%S)"
if [[ "$DRY_RUN" == 1 ]]; then
  LOG_FILE="/dev/null"
else
  mkdir -p "$LOG_DIR"; chmod 0750 "$LOG_DIR"
  LOG_FILE="$LOG_DIR/first-boot_${RUN_ID}.log"
fi

printf '%s%s' "$C_CYAN" "$C_BOLD"
cat <<'ART'
   ███████╗██╗    ██╗ █████╗ ██████╗ ███╗   ███╗     ██████╗ ███████╗
   ██╔════╝██║    ██║██╔══██╗██╔══██╗████╗ ████║    ██╔═══██╗██╔════╝
   ███████╗██║ █╗ ██║███████║██████╔╝██╔████╔██║    ██║   ██║███████╗
   ╚════██║██║███╗██║██╔══██║██╔══██╗██║╚██╔╝██║    ██║   ██║╚════██║
   ███████║╚███╔███╔╝██║  ██║██║  ██║██║ ╚═╝ ██║    ╚██████╔╝███████║
   ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚═════╝ ╚══════╝
ART
printf '%s   LUCILLE CORE AI "LLcy"  %s✚  I30LTZ Recovery · Dr. I30LTZ "MAD IT"%s\n' \
  "$C_MAG" "$C_RED" "$C_NC"
printf '%s   Ubuntu First Boot v%s · %s · profile=%s user=%s%s%s\n\n' \
  "$C_AMBER" "$KIT_VERSION" "$KIT_DATE" "$PROFILE" "$TARGET_USER" \
  "$([[ $DRY_RUN == 1 ]] && echo ' · DRY RUN')" "$C_NC"

if [[ "$ASSUME_YES" != 1 && "$DRY_RUN" != 1 ]]; then
  read -r -p "Apply secure first-boot setup now? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] || { info "Nothing changed. Try --dry-run to preview."; exit 0; }
fi

trap 'warn "stopped at line $LINENO (exit $?). Log: $LOG_FILE"' ERR

DONE=()
for mod in "$KIT_DIR"/modules/*.sh; do
  name="$(basename "$mod" .sh)"
  if [[ -n "$ONLY" ]] && ! in_list "$name" "$ONLY"; then continue; fi
  if [[ -n "$SKIP" ]] && in_list "$name" "$SKIP"; then info "skipped: $name"; continue; fi
  step "$name — $(sed -n 's/^# about: //p' "$mod")"
  # shellcheck source=/dev/null
  source "$mod"
  DONE+=("$name")
done

trap - ERR
step "Summary"
ok "modules run: ${DONE[*]:-none}"
if ((${#WARNINGS[@]})); then
  for w in "${WARNINGS[@]}"; do printf '  %s!%s %s\n' "$C_AMBER" "$C_NC" "$w"; done
fi
[[ "$DRY_RUN" == 1 ]] || info "log: $LOG_FILE   backups: $BACKUP_DIR"
printf '\n%sNext:%s  sudo %s/verify.sh     then reboot:  sudo reboot\n' \
  "$C_GREEN" "$C_NC" "$KIT_DIR"
