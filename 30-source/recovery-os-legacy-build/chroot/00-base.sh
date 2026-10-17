#!/usr/bin/env bash
# I30LTZ Recovery OS — Stage 00: Base system + locale + users
# Version: 1.0.0  |  2026-09-25
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

echo "DR. I30LTZ  |  00-base.sh starting..."

# ── Locale ─────────────────────────────────────────────────
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# ── APT sources ─────────────────────────────────────────────
cat > /etc/apt/sources.list << 'EOF'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
EOF

apt-get update -qq
apt-get upgrade -y -qq

# ── Core packages ───────────────────────────────────────────
apt-get install -y --no-install-recommends \
  systemd systemd-sysv dbus \
  sudo curl wget gnupg2 ca-certificates \
  openssh-client rsync \
  bash-completion vim nano \
  htop btop neofetch \
  net-tools iproute2 iputils-ping \
  ufw fail2ban \
  python3 python3-pip python3-venv \
  git jq bc coreutils \
  usbutils pciutils lshw \
  less man-db \
  zstd xz-utils gzip bzip2 \
  kbd console-setup \
  livecd-rootfs casper lupin-casper \
  initramfs-tools linux-generic

# ── Timezone ────────────────────────────────────────────────
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# ── Users ────────────────────────────────────────────────────
# Live user: dr-i30ltz (no password for live session)
useradd -m -s /bin/bash -G sudo,cdrom,floppy,audio,video,plugdev,netdev dr-i30ltz 2>/dev/null || true
echo "dr-i30ltz:dr-i30ltz" | chpasswd
echo "dr-i30ltz ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dr-i30ltz
chmod 440 /etc/sudoers.d/dr-i30ltz

# Disable root login
passwd -l root

# ── Hostname + hosts ─────────────────────────────────────────
echo "i30ltz-recovery" > /etc/hostname
cat > /etc/hosts << 'EOF'
127.0.0.1   localhost
127.0.1.1   i30ltz-recovery
::1         localhost ip6-localhost ip6-loopback
EOF

# ── Security hardening ───────────────────────────────────────
# UFW defaults
ufw default deny incoming
ufw default allow outgoing
ufw allow 7300/tcp comment "DR. I30LTZ SSE bridge"
ufw allow 5000/tcp comment "LucyServer API"

# Kernel hardening sysctl
cat > /etc/sysctl.d/99-i30ltz-secure.conf << 'EOF'
# I30LTZ Recovery OS — Security hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.randomize_va_space = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.core.somaxconn = 4096
vm.swappiness = 10
EOF

# ── OS ID ────────────────────────────────────────────────────
cat > /etc/os-release << 'EOF'
NAME="I30LTZ Recovery OS"
VERSION="1.0.0 (NIGHTFALL)"
ID=i30ltz-recovery
ID_LIKE=ubuntu
PRETTY_NAME="I30LTZ Recovery OS 1.0.0 (NIGHTFALL)"
VERSION_ID="1.0.0"
HOME_URL="https://github.com/i30ltz/recovery-os"
SUPPORT_URL="https://github.com/i30ltz/recovery-os/issues"
BUG_REPORT_URL="https://github.com/i30ltz/recovery-os/issues"
BUILD_ID=2026-09-25
EOF

echo "00-base.sh ✓ complete"
