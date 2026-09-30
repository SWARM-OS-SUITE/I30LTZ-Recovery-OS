#!/usr/bin/env bash
# =============================================================================
# SWARM_OS Suite · Dev Workstation — migrate from first-boot kit v1.0.0
# Version: 2.0.0 | Date: 2026-09-30
#
# v1.0.0 put SWARM_OS and I30LTZ Recovery OS identity on one Ubuntu machine.
# This laptop is the dev workstation, so this script:
#   1. renames v1 config files (60-swarm-* → 60-firstboot-*), keeping settings
#   2. removes the two "this machine IS the OS" identity files
#   3. removes the empty /opt/swarm_os, /etc/swarm_os, … folders
# Everything it touches is backed up first. Your ~/SWARM_OS folders and all
# installed tools stay exactly as they are.
#   sudo bash migrate-from-v1.sh --dry-run
#   sudo bash migrate-from-v1.sh
# =============================================================================
set -Eeuo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib/common.sh
source "$KIT_DIR/../common/lib/common.sh"
BACKUP_DIR="/var/backups/dev-workstation-first-boot/migrate-v1_$(date +%Y%m%d-%H%M%S)"
[[ "${1:-}" == --dry-run ]] && DRY_RUN=1
[[ $EUID -eq 0 ]] || die "run as root:  sudo bash $0"
trap 'warn "stopped at line $LINENO — nothing after this ran. Backups: $BACKUP_DIR"' ERR

step "1 · rename v1 config files (settings kept)"
pairs=(
  /etc/sysctl.d/60-swarm-hardening.conf:/etc/sysctl.d/60-firstboot-hardening.conf
  /etc/sysctl.d/61-swarm-performance.conf:/etc/sysctl.d/61-firstboot-performance.conf
  /etc/apt/apt.conf.d/52swarm-unattended:/etc/apt/apt.conf.d/52firstboot-unattended
  /etc/security/limits.d/60-swarm-nocore.conf:/etc/security/limits.d/60-firstboot-nocore.conf
  /etc/systemd/coredump.conf.d/60-swarm.conf:/etc/systemd/coredump.conf.d/60-firstboot.conf
  /etc/ssh/sshd_config.d/60-swarm-hardening.conf:/etc/ssh/sshd_config.d/60-firstboot-hardening.conf
  /etc/dconf/db/local.d/60-swarm-security:/etc/dconf/db/local.d/60-firstboot-security
)
for pair in "${pairs[@]}"; do
  old="${pair%%:*}" new="${pair##*:}"
  [[ -e "$old" ]] || continue
  backup_file "$old"
  if [[ -e "$new" ]]; then run rm -f "$old"; ok "removed duplicate: $old"
  else run mv "$old" "$new"; ok "renamed: $old → $new"; fi
done

step "2 · remove OS identity files (this laptop is the dev workstation)"
for f in /etc/swarm_os/release /etc/swarm_os/lucille.toml /etc/i30ltz/release; do
  [[ -e "$f" ]] || continue
  backup_file "$f"; run rm -f "$f"; ok "removed: $f"
done

step "3 · remove empty v1 SWARM_OS folders"
for d in /opt/swarm_os/lucille/models /opt/swarm_os/lucille /opt/swarm_os/bin /opt/swarm_os \
         /etc/swarm_os /var/lib/swarm_os /var/log/swarm_os; do
  [[ -d "$d" ]] || continue
  if [[ -z "$(ls -A "$d")" ]]; then run rmdir "$d"; ok "removed empty: $d"
  else warn "kept (has files — move them to /opt/suite-dev yourself): $d"; fi
done

step "4 · reload"
run sysctl --system >/dev/null 2>&1 || warn "sysctl reported unknown keys (settings still load at next boot)"
have dconf && run dconf update
ok "migration done. Backups: $BACKUP_DIR"
getent group swarm >/dev/null && info "old 'swarm' group left in place (harmless). Remove with:  sudo groupdel swarm"
printf '\nNext:  sudo bash %s/first-boot.sh --user %s   then   sudo bash %s/verify.sh\n' \
  "$KIT_DIR" "${SUDO_USER:-YOURNAME}" "$KIT_DIR"
