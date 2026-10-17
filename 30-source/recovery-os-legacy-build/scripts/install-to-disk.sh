#!/usr/bin/env bash
# ============================================================
#  DR. I30LTZ — Install Recovery OS to Physical Disk
#  Version: 1.0.0  |  2026-09-25
#  Replaces Xubuntu-style installer for headless/TUI install
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; WHT='\033[1;37m'; RST='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLU}[I30LTZ]${RST} $*"; }
ok()   { echo -e "${GRN}[ OK   ]${RST} $*"; }
warn() { echo -e "${YLW}[ WARN ]${RST} $*"; }
die()  { echo -e "${RED}[FATAL ]${RST} $*"; exit 1; }
ask()  { echo -ne "${WHT}${BOLD}[  ?   ]${RST} $* "; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

echo -e "${RED}${BOLD}"
cat << 'EOF'
 ██████╗ ██████╗       ██╗██████╗  ██████╗ ██╗  ████████╗███████╗
 ██╔══██╗██╔══██╗      ██║╚════██╗██╔═══██╗██║  ╚══██╔══╝╚════██║
 ██║  ██║██████╔╝      ██║ █████╔╝██║   ██║██║     ██║       ██╔╝
 ██║  ██║██╔══██╗      ██║ ╚═══██╗██║   ██║██║     ██║      ██╔╝
 ██████╔╝██║  ██║      ██║██████╔╝╚██████╔╝███████╗██║      ██║
 ╚═════╝ ╚═╝  ╚═╝      ╚═╝╚═════╝  ╚═════╝ ╚══════╝╚═╝      ╚═╝
  INSTALL TO DISK — v1.0.0 — 2026-09-25
EOF
echo -e "${RST}"
warn "This script will ERASE the target disk. All data will be lost."
echo ""

# ── Select target disk ───────────────────────────────────────
log "Available disks:"
lsblk -d -o NAME,SIZE,MODEL --noheadings | grep -v loop | while read -r name size model; do
  echo "    /dev/${name}  ${size}  ${model}"
done
echo ""
ask "Target disk (e.g. sda, nvme0n1): "
read -r DISK_NAME
TARGET="/dev/${DISK_NAME}"
[[ -b "$TARGET" ]] || die "Not a block device: $TARGET"

# Confirm
echo ""
warn "Will WIPE: $TARGET ($(lsblk -d -o SIZE --noheadings "$TARGET" | tr -d ' '))"
ask "Type 'ERASE' to confirm: "
read -r CONFIRM
[[ "$CONFIRM" == "ERASE" ]] || { echo "Aborted."; exit 0; }

# ── Partition ────────────────────────────────────────────────
log "Partitioning $TARGET (GPT)..."
# Layout:  EFI (512MB) | SWAP (2GB) | ROOT (rest)
parted -s "$TARGET" \
  mklabel gpt \
  mkpart "EFI" fat32 1MiB 513MiB \
  set 1 esp on \
  mkpart "swap" linux-swap 513MiB 2561MiB \
  mkpart "I30LTZ_ROOT" ext4 2561MiB 100%

sleep 2
partprobe "$TARGET"

# Set partition names
if [[ "$TARGET" =~ nvme ]]; then
  EFI="${TARGET}p1"
  SWP="${TARGET}p2"
  ROOT="${TARGET}p3"
else
  EFI="${TARGET}1"
  SWP="${TARGET}2"
  ROOT="${TARGET}3"
fi

# ── Format ───────────────────────────────────────────────────
log "Formatting..."
mkfs.fat -F32 -n "I30LTZ_EFI" "$EFI"
mkswap -L "i30ltz-swap" "$SWP"
mkfs.ext4 -L "I30LTZ_ROOT" -F "$ROOT"
ok "Partitions formatted"

# ── Mount ────────────────────────────────────────────────────
MOUNT_ROOT="/mnt/i30ltz-install"
mkdir -p "$MOUNT_ROOT"
mount "$ROOT" "$MOUNT_ROOT"
mkdir -p "${MOUNT_ROOT}/boot/efi"
mount "$EFI" "${MOUNT_ROOT}/boot/efi"

# ── Copy squashfs ────────────────────────────────────────────
log "Extracting filesystem (this takes several minutes)..."
SQUASHFS="/run/live/medium/live/filesystem.squashfs"
[[ -f "$SQUASHFS" ]] || die "Squashfs not found at $SQUASHFS"
unsquashfs -f -d "$MOUNT_ROOT" "$SQUASHFS"
ok "Filesystem extracted"

# ── Generate fstab ───────────────────────────────────────────
log "Writing fstab..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
EFI_UUID=$(blkid -s UUID -o value "$EFI")
SWP_UUID=$(blkid -s UUID -o value "$SWP")

cat > "${MOUNT_ROOT}/etc/fstab" << FSTAB
# I30LTZ Recovery OS — fstab  (generated $(date +%Y-%m-%d))
UUID=${ROOT_UUID}  /          ext4  errors=remount-ro  0 1
UUID=${EFI_UUID}   /boot/efi  vfat  umask=0077         0 1
UUID=${SWP_UUID}   none       swap  sw                 0 0
FSTAB

# ── Bind mounts for chroot ────────────────────────────────────
for f in dev dev/pts proc sys run; do
  mount --bind "/$f" "${MOUNT_ROOT}/$f"
done

# ── Install GRUB ─────────────────────────────────────────────
log "Installing GRUB..."
chroot "$MOUNT_ROOT" grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id="I30LTZ_Recovery" \
  --recheck \
  "$TARGET"
chroot "$MOUNT_ROOT" update-grub

# ── Set hostname ─────────────────────────────────────────────
echo "i30ltz-recovery" > "${MOUNT_ROOT}/etc/hostname"

# ── Unmount ──────────────────────────────────────────────────
for f in dev/pts dev proc sys run; do
  umount -lf "${MOUNT_ROOT}/$f" 2>/dev/null || true
done
umount "${MOUNT_ROOT}/boot/efi"
umount "$MOUNT_ROOT"

echo ""
ok "═══════════════════════════════════════════════"
ok "  I30LTZ Recovery OS installed to $TARGET"
ok "  Remove the USB drive and reboot."
ok "═══════════════════════════════════════════════"
