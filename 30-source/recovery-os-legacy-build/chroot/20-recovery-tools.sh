#!/usr/bin/env bash
# I30LTZ Recovery OS — Stage 20: Enterprise Recovery Tooling
# Version: 1.0.0  |  2026-09-25
# Tools: disk, filesystem, boot, data recovery, network, security
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "DR. I30LTZ  |  20-recovery-tools.sh starting..."

# ── Disk + Filesystem ────────────────────────────────────────
apt-get install -y --no-install-recommends \
  testdisk photorec \
  gparted parted fdisk gdisk \
  e2fsprogs dosfstools ntfs-3g \
  btrfs-progs xfsprogs f2fs-tools \
  smartmontools nvme-cli \
  hdparm sdparm \
  lvm2 mdadm \
  cryptsetup cryptsetup-bin \
  extundelete \
  foremost \
  safecopy \
  ddrescue \
  dc3dd \
  gddrescue \
  ncdu \
  baobab \
  bleachbit

# ── Boot Repair ──────────────────────────────────────────────
apt-get install -y --no-install-recommends \
  grub-pc grub-efi-amd64 grub2-common \
  efibootmgr \
  os-prober \
  boot-repair

# ── Memory diagnostics ───────────────────────────────────────
apt-get install -y --no-install-recommends \
  memtest86+ \
  memtester

# ── Hardware diagnostics ─────────────────────────────────────
apt-get install -y --no-install-recommends \
  stress-ng \
  s-tui \
  dmidecode \
  inxi \
  lm-sensors \
  cpu-x \
  hwinfo \
  acpi

# ── Network tools ─────────────────────────────────────────────
apt-get install -y --no-install-recommends \
  nmap \
  wireshark-common tshark \
  iperf3 \
  ethtool \
  ncat \
  whois \
  dnsutils \
  traceroute \
  mtr \
  netcat-openbsd

# ── Backup + Clone ───────────────────────────────────────────
apt-get install -y --no-install-recommends \
  rsync \
  rclone \
  borgbackup \
  squashfs-tools \
  partclone

# ── Password + Credential Recovery ───────────────────────────
apt-get install -y --no-install-recommends \
  chntpw \
  john \
  hashcat

# ── Security audit ───────────────────────────────────────────
apt-get install -y --no-install-recommends \
  lynis \
  rkhunter \
  clamav clamav-freshclam \
  chkrootkit \
  aide \
  auditd

# ── File recovery viewers ────────────────────────────────────
apt-get install -y --no-install-recommends \
  binwalk \
  hexedit \
  ghex \
  xxd

# ── DR. I30LTZ Recovery desktop shortcuts ───────────────────
mkdir -p /usr/local/share/applications
cat > /usr/local/share/applications/dr-i30ltz-recovery.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=DR. I30LTZ Recovery
Comment=AI Recovery Evaluation System v1.0.0
Exec=/opt/i30ltz/bin/i30ltz-recovery
Icon=/opt/i30ltz/assets/dr-i30ltz.png
Terminal=false
Categories=System;Recovery;
StartupNotify=true
EOF

cat > /usr/local/share/applications/gparted.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=GParted (Partition Editor)
Exec=sudo gparted
Icon=gparted
Terminal=false
Categories=System;Recovery;
EOF

cat > /usr/local/share/applications/testdisk.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=TestDisk (Partition Recovery)
Exec=xfce4-terminal -e "sudo testdisk"
Icon=utilities-terminal
Terminal=false
Categories=System;Recovery;
EOF

# ── Custom recovery scripts ───────────────────────────────────
mkdir -p /opt/i30ltz/scripts

cat > /opt/i30ltz/scripts/quick-scan.sh << 'SCRIPT'
#!/usr/bin/env bash
# DR. I30LTZ Quick System Scan
# Outputs JSON to stdout for MAD IT to process
set -euo pipefail
echo "{"
echo "  \"timestamp\": \"$(date -Iseconds)\","
echo "  \"hostname\": \"$(hostname)\","
echo "  \"uptime\": \"$(uptime -p)\","
echo "  \"disk_health\": ["
for dev in $(lsblk -d -o NAME --noheadings | grep -v loop); do
  health=$(smartctl -H /dev/$dev 2>/dev/null | grep "overall-health" | awk '{print $6}' || echo "UNKNOWN")
  echo "    {\"device\": \"/dev/$dev\", \"health\": \"$health\"},"
done
echo "  ],"
echo "  \"memory_mb\": $(free -m | awk '/^Mem:/{print $2}\'),"
echo "  \"cpu_count\": $(nproc),"
echo "  \"temps\": $(sensors -j 2>/dev/null || echo '{}')"
echo "}"
SCRIPT
chmod +x /opt/i30ltz/scripts/quick-scan.sh

cat > /opt/i30ltz/scripts/disk-rescue.sh << 'SCRIPT'
#!/usr/bin/env bash
# DR. I30LTZ Disk Rescue — interactive wrapper
# Usage: ./disk-rescue.sh <source_device> <output_dir>
SRC="${1:-}"
OUT="${2:-/mnt/rescue}"
[[ -z "$SRC" ]] && { echo "Usage: $0 <source> <output_dir>"; exit 1; }
mkdir -p "$OUT"
echo "[DR. I30LTZ] Starting ddrescue rescue: $SRC → $OUT/rescue.img"
ddrescue -d -r3 -n "$SRC" "$OUT/rescue.img" "$OUT/rescue.log"
echo "[DR. I30LTZ] Phase 2: retry bad sectors"
ddrescue -d -r3 "$SRC" "$OUT/rescue.img" "$OUT/rescue.log"
echo "[DR. I30LTZ] Rescue complete. Image: $OUT/rescue.img"
SCRIPT
chmod +x /opt/i30ltz/scripts/disk-rescue.sh

echo "20-recovery-tools.sh ✓ complete"
