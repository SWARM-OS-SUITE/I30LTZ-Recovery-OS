# shellcheck shell=bash
# =============================================================================
# Shared first-boot runner · v2.0.0 · 2026-09-30
# Sourced by a kit's first-boot.sh. Never run directly.
#
# The kit sets before sourcing:
#   KIT_ID KIT_TITLE KIT_VERSION KIT_DATE KIT_DIR   (strings)
#   FEATURE_GAMING=0|1   gaming tuning (i386 libs, max_map_count, multiverse)
#   NEEDS_USER=0|1       kit organizes a user's home, so --user is required
#   kit_banner()         prints the kit's banner
# Modules = system/common/modules/*.sh + $KIT_DIR/modules/*.sh, run in number order.
# =============================================================================
set -Eeuo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$COMMON_DIR/../.." && pwd)"
# shellcheck source=lib/common.sh
source "$COMMON_DIR/lib/common.sh"
LOG_DIR="/var/log/$KIT_ID"
BACKUP_DIR="/var/backups/$KIT_ID"

ONLY=""
SKIP=""
ENABLE_SSH=0
ASSUME_YES=0
TARGET_USER="${SUDO_USER:-}"

# All modules, sorted by file name (so 00-, 10-, … run in order across both dirs)
mapfile -t MODULES < <(
  for m in "$COMMON_DIR"/modules/*.sh "$KIT_DIR"/modules/*.sh; do
    [[ -f "$m" ]] && printf '%s\t%s\n' "$(basename "$m")" "$m"
  done | sort | cut -f2
)

usage() {
  cat <<EOF
${KIT_TITLE} · First Boot v${KIT_VERSION} (${KIT_DATE})

Usage: sudo bash $0 [options]
  --user NAME          main user account (default: \$SUDO_USER)
  --only MOD[,MOD]     run only these modules (e.g. 20-harden)
  --skip MOD[,MOD]     skip these modules
  --enable-ssh         install + harden OpenSSH (off by default = safer)
  --dry-run            show what would happen, change nothing
  -y, --yes            don't ask for confirmation
  -h, --help           this help

Modules:
EOF
  for m in "${MODULES[@]}"; do
    printf '  %-22s %s\n' "$(basename "$m" .sh)" "$(sed -n 's/^# about: //p' "$m")"
  done
}

while (($#)); do
  case "$1" in
    --user)       TARGET_USER="${2:?}"; shift 2 ;;
    --only)       ONLY="${2:?}"; shift 2 ;;
    --skip)       SKIP="${2:?}"; shift 2 ;;
    --enable-ssh) ENABLE_SSH=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -y|--yes)     ASSUME_YES=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    --profile)    die "--profile was removed in v2.0.0: each OS now has its own kit (see system/README.md)" ;;
    *) usage; die "unknown option: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "run as root:  sudo bash $0"
TARGET_HOME=""
if [[ -n "$TARGET_USER" && "$TARGET_USER" != root ]]; then
  id "$TARGET_USER" >/dev/null 2>&1 || die "user not found: $TARGET_USER"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
elif [[ "$NEEDS_USER" == 1 ]]; then
  die "tell me whose home to set up:  --user YOURNAME"
else
  TARGET_USER=""
fi

export ENABLE_SSH DRY_RUN TARGET_USER TARGET_HOME KIT_DIR REPO_DIR FEATURE_GAMING
# shellcheck disable=SC2034  # read by modules
APT_DIRTY=0

in_list() { [[ ",$2," == *",$1,"* ]]; }

RUN_ID="$(date +%Y-%m-%d_%H%M%S)"
if [[ "$DRY_RUN" == 1 ]]; then
  LOG_FILE="/dev/null"
else
  mkdir -p "$LOG_DIR"; chmod 0750 "$LOG_DIR"
  LOG_FILE="$LOG_DIR/first-boot_${RUN_ID}.log"
fi

kit_banner
printf '%s   %s · First Boot v%s · %s · user=%s%s%s\n\n' \
  "$C_AMBER" "$KIT_TITLE" "$KIT_VERSION" "$KIT_DATE" "${TARGET_USER:-none}" \
  "$([[ $DRY_RUN == 1 ]] && echo ' · DRY RUN')" "$C_NC"

if [[ "$ASSUME_YES" != 1 && "$DRY_RUN" != 1 ]]; then
  read -r -p "Apply ${KIT_TITLE} first-boot setup now? [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]] || { info "Nothing changed. Try --dry-run to preview."; exit 0; }
fi

trap 'warn "stopped at line $LINENO (exit $?). Log: $LOG_FILE"' ERR

DONE=()
for mod in "${MODULES[@]}"; do
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
printf '\n%sNext:%s  sudo bash %s/verify.sh     then reboot\n' "$C_GREEN" "$C_NC" "$KIT_DIR"
