# shellcheck shell=bash
# about: I30LTZ Recovery · Dr. I30LTZ "MAD IT" — repair + data-recovery toolkit
# I30LTZ Recovery OS first boot v2.0.0 · 2026-09-30
# Also reused by the dev-workstation kit as a test bench (WRITE_OS_IDENTITY=0).

# ── Disk health + imaging + carving ────────────────────────────────────────
apt_install smartmontools nvme-cli hdparm gddrescue testdisk \
  ntfs-3g exfatprogs dosfstools btrfs-progs xfsprogs e2fsprogs \
  cryptsetup mdadm lvm2 gdisk parted
apt_optional foremost scalpel partclone gparted dcfldd ddrescueview \
  sleuthkit chntpw clamav clamav-freshclam rkhunter memtest86+ \
  hwinfo inxi lshw dmidecode stress-ng

run systemctl enable --now clamav-freshclam 2>/dev/null || warn "clamav-freshclam not started"
# Weekly SMART self-checks + mail to root journal
run systemctl enable --now smartmontools 2>/dev/null || run systemctl enable --now smartd 2>/dev/null || true

# ── MAD IT home: /opt/i30ltz + private case store ──────────────────────────
getent group i30ltz >/dev/null || run groupadd --system i30ltz
[[ -n "$TARGET_USER" ]] && run usermod -aG i30ltz "$TARGET_USER"
run install -d -o root -g i30ltz -m 0755 /opt/i30ltz /opt/i30ltz/bin /opt/i30ltz/models /etc/i30ltz
# Cases hold other people's data: group-only, never world-readable
run install -d -o root -g i30ltz -m 2770 /var/lib/i30ltz /var/lib/i30ltz/cases /var/log/i30ltz

if [[ -f "$REPO_DIR/native/config/i30ltz.toml" && ! -f /etc/i30ltz/i30ltz.toml ]]; then
  run install -m 0644 "$REPO_DIR/native/config/i30ltz.toml" /etc/i30ltz/i30ltz.toml
fi

# ── Evidence safety ────────────────────────────────────────────────────────
# Recovery rule #1: never write to the patient drive. This helper flips a
# disk and all its partitions to kernel-level read-only before you image it.
write_file /opt/i30ltz/bin/i30ltz-writeblock 0755 <<'SH'
#!/usr/bin/env bash
# Dr. I30LTZ "MAD IT" — software write-blocker v1.0.0 · 2026-09-30
# usage: sudo i30ltz-writeblock on|off|status /dev/sdX
set -euo pipefail
mode="${1:-status}"; dev="${2:-}"
[[ -b "$dev" ]] || { echo "usage: sudo $0 on|off|status /dev/sdX"; lsblk -dpno NAME,SIZE,MODEL; exit 1; }
# shellcheck disable=SC2207
parts=("$dev" $(lsblk -lnpo NAME "$dev" | tail -n +2))
case "$mode" in
  on)  for p in "${parts[@]}"; do blockdev --setro "$p"; done; echo "🔒 READ-ONLY: ${parts[*]}" ;;
  off) for p in "${parts[@]}"; do blockdev --setrw "$p"; done; echo "🔓 read-write: ${parts[*]}" ;;
  status) for p in "${parts[@]}"; do printf '%-16s %s\n' "$p" "$([[ $(blockdev --getro "$p") == 1 ]] && echo 'READ-ONLY' || echo 'read-write')"; done ;;
  *) echo "mode must be on|off|status"; exit 1 ;;
esac
SH
run ln -sf /opt/i30ltz/bin/i30ltz-writeblock /usr/local/bin/i30ltz-writeblock

# Machine identity — only on a real I30LTZ Recovery OS install
if [[ "${WRITE_OS_IDENTITY:-1}" == 1 ]]; then
  write_file /etc/i30ltz/release 0644 <<'CFG'
# I30LTZ Recovery OS — machine identity
OS="I30LTZ Recovery OS"
ASSISTANT="Dr. I30LTZ (MAD IT)"
FIRST_BOOT_KIT="2.0.0"
FIRST_BOOT_DATE="2026-09-30"
CFG
fi
ok "MAD IT toolkit ready: /opt/i30ltz, cases in /var/lib/i30ltz/cases (group: i30ltz)"
