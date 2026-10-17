#!/usr/bin/env bash
# I30LTZ Recovery OS - Write ISO to USB + persistence + AI model
# Version: 0.3.0-alpha | Date: 2026-10-05
# Run: sudo bash make-persistent-usb.sh /dev/sdX [path/to.iso]
# Steps: dd ISO -> append ext4 partition labelled 'persistence' (Debian live-boot)
#        using ALL free space, with persistence.conf '/ union'
#        -> copy staged qwen2.5:7b into it (if staged)
# SAFETY: refuses system disk, requires typing the device name to confirm.
# Needs a >=16 GB stick (ISO ~3 GB + 4.7 GB model + working space).
# -------------------------------------------------------
set -e
DEV="$1"
ROOT=/mnt/recoverybuild
ISO="${2:-$(ls -t $ROOT/10-releases/*.iso 2>/dev/null | head -1)}"
MODELS="$ROOT/50-backends/models"

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
[ -b "$DEV" ] || { echo "Usage: sudo $0 /dev/sdX [iso]"; exit 1; }
[ -f "$ISO" ] || { echo "No ISO found. Run build.sh first."; exit 1; }

# Refuse the disk holding / or /mnt/recoverybuild
for m in / "$ROOT"; do
  src=$(findmnt -n -o SOURCE --target "$m" 2>/dev/null || true)
  pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
  [ -n "$pk" ] && [ "/dev/$pk" = "$DEV" ] && { echo "REFUSING: $DEV holds $m"; exit 1; }
done

SIZE_GB=$(( $(blockdev --getsize64 "$DEV") / 1000000000 ))
echo "Target : $DEV  (${SIZE_GB} GB)  $(lsblk -dno MODEL "$DEV")"
echo "ISO    : $ISO"
[ "$SIZE_GB" -ge 16 ] || { echo "Stick too small (<16 GB)"; exit 1; }
echo "ALL DATA ON $DEV WILL BE ERASED."
read -r -p "Type the device name ($DEV) to confirm: " ANS
[ "$ANS" = "$DEV" ] || { echo "Aborted."; exit 1; }

umount ${DEV}* 2>/dev/null || true
echo "[1/4] Writing ISO..."
dd if="$ISO" of="$DEV" bs=4M status=progress conv=fsync
sync; partprobe "$DEV"; sleep 2

echo "[2/4] Creating persistence partition in free space..."
echo ",,L" | sfdisk --append "$DEV"
partprobe "$DEV"; sleep 2
PART=$(lsblk -nrpo NAME "$DEV" | tail -1)
echo "[3/4] Formatting $PART as ext4 (label: persistence)..."
mkfs.ext4 -F -L persistence "$PART"
MNT=$(mktemp -d)
mount "$PART" "$MNT"
echo "/ union" > "$MNT/persistence.conf"
sync; umount "$MNT"; rmdir "$MNT"

echo "[4/4] Staging AI model..."
if [ -d "$MODELS/blobs" ]; then
  MNT=$(mktemp -d)
  mount "$PART" "$MNT"
  mkdir -p "$MNT/usr/share/ollama/.ollama"
  rsync -a --info=progress2 "$MODELS" "$MNT/usr/share/ollama/.ollama/"
  sync; umount "$MNT"; rmdir "$MNT"
  echo "     model copied (ollama.service re-owns it on boot)"
else
  echo "     no staged model - run 50-backends/stage-model.sh first, or it pulls on first boot"
fi
echo ""
echo "DONE. Boot $DEV. Persistence active (label persistence, boot=live ... persistence)."
