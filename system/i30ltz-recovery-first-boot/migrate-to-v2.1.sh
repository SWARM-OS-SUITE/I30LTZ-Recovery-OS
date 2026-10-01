#!/usr/bin/env bash
# =============================================================================
# I30LTZ Recovery OS — clean up an earlier first-boot run before kit v2.1.0
# Version: 2.1.0 | Date: 2026-10-01
#
# For an existing external Ubuntu install that becomes I30LTZ Recovery OS
# after it already ran:
#   v1.0.0  ubuntu-first-boot --profile both   (60-swarm-* files, SWARM identity)
#   v2.0.0  dev-workstation-first-boot         (/etc/suite-dev, /opt/suite-dev)
# This script:
#   1. renames v1 config files (60-swarm-* → 60-firstboot-*), keeping settings
#   2. removes SWARM_OS + dev-workstation identity files (this drive is Recovery OS)
#   3. removes empty v1/v2 folders; anything with files is kept and reported
# It never touches /etc/i30ltz, installed tools, Flatpak apps or ~/SWARM_OS.
# Everything it changes is backed up first.
#   sudo bash migrate-to-v2.1.sh --dry-run
#   sudo bash migrate-to-v2.1.sh
# =============================================================================
set -Eeuo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib/common.sh
source "$KIT_DIR/../common/lib/common.sh"
BACKUP_DIR="/var/backups/i30ltz-first-boot/migrate-v2.1_$(date +%Y%m%d-%H%M%S)"
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

step "2 · remove identity files that don't belong on Recovery OS"
for f in /etc/swarm_os/release /etc/swarm_os/lucille.toml /etc/suite-dev/release; do
  [[ -e "$f" ]] || continue
  backup_file "$f"; run rm -f "$f"; ok "removed: $f"
done

step "3 · remove empty v1/v2 folders"
for d in /opt/swarm_os/lucille/models /opt/swarm_os/lucille /opt/swarm_os/bin /opt/swarm_os \
         /etc/swarm_os /var/lib/swarm_os /var/log/swarm_os \
         /opt/suite-dev/models /opt/suite-dev/iso-test /opt/suite-dev /etc/suite-dev; do
  [[ -d "$d" ]] || continue
  if [[ -z "$(ls -A "$d")" ]]; then run rmdir "$d"; ok "removed empty: $d"
  else warn "kept (has files — move them to /var/lib/i30ltz/swarm-build yourself): $d"; fi
done

step "4 · reload"
run sysctl --system >/dev/null 2>&1 || warn "sysctl reported unknown keys (settings still load at next boot)"
have dconf && run dconf update
ok "clean-up done. Backups: $BACKUP_DIR"
for g in swarm suitedev; do
  getent group "$g" >/dev/null && info "old '$g' group left in place (harmless). Remove with:  sudo groupdel $g"
done
printf '\nNext:  sudo bash %s/first-boot.sh --user %s   then   sudo bash %s/verify.sh\n' \
  "$KIT_DIR" "${SUDO_USER:-\$USER}" "$KIT_DIR"
