#!/usr/bin/env bash
# =============================================================================
# I30LTZ Recovery OS — install a built image onto an external drive
# v0.1.0 · 2026-10-01
#
#   sudo bash install-to-drive.sh <out/vX_DATE dir> <disk> [--root-size 40G] [--dry-run]
#   e.g. sudo bash install-to-drive.sh out/v0.1.0_2026-10-01 /dev/sdb --dry-run
#
# What it does: adds TWO new partitions (ESP + root) in the drive's largest
# FREE space and copies the OS into them. Existing partitions — like the
# boltz data partition — are never written, moved or resized.
#
# It refuses to run when the target:
#   • is an internal NVMe / not USB-attached        (SWARM_OS lives there)
#   • holds the running system or anything mounted
#   • is MBR-partitioned with partitions on it       (conversion could lose data)
#   • already has an OS root partition               (two would confuse boot)
#   • has too little free space
# =============================================================================
set -Eeuo pipefail
ROOT_TYPE=4f68bce3-e8cd-4db1-96e7-fbcaf984b709   # GPT "Linux root (x86-64)"
ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
MIN_ROOT_GB=12

red() { printf '\033[1;31m%s\033[0m\n' "$*"; }
yel() { printf '\033[1;33m%s\033[0m\n' "$*"; }
grn() { printf '\033[1;32m%s\033[0m\n' "$*"; }
die() { red "✋ $*"; exit 1; }

dir="" disk="" root_size="" dry=0 allow_non_usb=0
while (($#)); do
  case "$1" in
    --root-size) root_size="${2:?}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --i-know-its-not-usb) allow_non_usb=1; shift ;;   # loop-device tests only
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) if [[ -z "$dir" ]]; then dir="$1"; elif [[ -z "$disk" ]]; then disk="$1"; else die "unexpected: $1"; fi; shift ;;
  esac
done
[[ -n "$dir" && -n "$disk" ]] || { sed -n '5,7p' "$0"; exit 1; }
[[ $EUID -eq 0 ]] || die "run as root: sudo bash $0 …"
for c in sgdisk sfdisk partprobe e2fsck resize2fs tune2fs numfmt blkid; do
  command -v "$c" >/dev/null || die "missing tool '$c' — install with: sudo apt install gdisk fdisk parted e2fsprogs"
done

# ── 1 · the image ──────────────────────────────────────────────────────────
esp_img=$(ls "$dir"/*.esp.raw 2>/dev/null | head -1 || true)
root_img=$(ls "$dir"/*.root-x86-64.raw 2>/dev/null | head -1 || true)
[[ -f "$esp_img" && -f "$root_img" ]] || die "no split ESP/root images in $dir — build with os/build.sh first"
yel "verifying image checksums…"
( cd "$dir" && sha256sum --quiet -c SHA256SUMS ) || die "checksum mismatch — rebuild the image"
esp_bytes=$(stat -c %s "$esp_img"); root_img_bytes=$(stat -c %s "$root_img")

# ── 2 · the target disk ────────────────────────────────────────────────────
[[ -b "$disk" ]] || die "$disk is not a block device"
[[ "$(lsblk -dno TYPE "$disk")" == disk || "$(lsblk -dno TYPE "$disk")" == loop ]] || die "$disk is a partition — give the whole disk (e.g. /dev/sdb)"
tran=$(lsblk -dno TRAN "$disk" | xargs || true)
[[ "$disk" == /dev/nvme* ]] && die "$disk is an internal NVMe — that's SWARM_OS's drive. Refusing."
if [[ "$tran" != usb && $allow_non_usb == 0 ]]; then
  die "$disk is not USB-attached (transport: ${tran:-unknown}). Recovery OS belongs on the external drive."
fi
root_src=$(findmnt -no SOURCE / || true)
if lsblk -no PKNAME "$(readlink -f "$root_src" 2>/dev/null || echo /dev/null)" 2>/dev/null | grep -qx "$(basename "$disk")"; then
  die "$disk holds the system you're running right now. Boot from a different drive first."
fi
if lsblk -lnpo MOUNTPOINTS "$disk" | grep -q '[^[:space:]]'; then
  lsblk -po NAME,SIZE,MOUNTPOINTS "$disk"
  die "partitions on $disk are mounted — unmount them first (e.g. sudo umount /mnt/boltz)"
fi
pttype=$(blkid -p -o value -s PTTYPE "$disk" 2>/dev/null || true)
nparts=$(lsblk -lnpo TYPE "$disk" | grep -c part || true)
if [[ "$pttype" == dos && $nparts -gt 0 ]]; then
  die "$disk uses an MBR partition table with partitions on it. Converting could lose data — back up, then make it GPT."
fi
if lsblk -lnpo PARTTYPE "$disk" | grep -qi "$ROOT_TYPE"; then
  die "$disk already has an OS root partition. Remove the old one first so boot stays unambiguous."
fi
model=$(lsblk -dno MODEL "$disk" | xargs || true); size_h=$(lsblk -dno SIZE "$disk" | xargs)

# ── 3 · free space (largest gap, 1 MiB aligned) ────────────────────────────
sector=$(blockdev --getss "$disk")
new_table=0
if [[ -z "$pttype" ]]; then
  new_table=1
  total=$(blockdev --getsz "$disk")            # 512-byte units
  gap_start=2048; gap_end=$(( total * 512 / sector - 34 - 1 ))
else
  read -r gap_start gap_end < <(sfdisk -F -q "$disk" 2>/dev/null \
    | awk 'NF>=3 && $1 ~ /^[0-9]+$/ {print $1, $2, $3}' | sort -k3 -n | tail -1 | cut -d' ' -f1,2) || true
  [[ -n "${gap_start:-}" ]] || die "no free space on $disk — shrink a partition (gparted) or use another drive"
fi
align=$(( 1048576 / sector ))
gap_start=$(( (gap_start + align - 1) / align * align ))
gap_bytes=$(( (gap_end - gap_start + 1) * sector ))
esp_sectors=$(( esp_bytes / sector ))
if [[ -n "$root_size" ]]; then
  root_bytes=$(numfmt --from=iec "${root_size%B}")
else
  root_bytes=$(( gap_bytes - esp_bytes - 1048576 ))
fi
root_bytes=$(( root_bytes / 1048576 * 1048576 ))
(( root_bytes >= MIN_ROOT_GB * 1024**3 )) || die "only $(numfmt --to=iec $gap_bytes) free on $disk — need at least $((MIN_ROOT_GB+1))G"
(( root_bytes >= root_img_bytes )) || die "root size smaller than the OS image ($(numfmt --to=iec $root_img_bytes))"
(( esp_bytes + root_bytes <= gap_bytes )) || die "not enough free space: need $(numfmt --to=iec $((esp_bytes+root_bytes))), have $(numfmt --to=iec $gap_bytes)"
esp_start=$gap_start; esp_end=$(( esp_start + esp_sectors - 1 ))
root_start=$(( esp_end + 1 )); root_end=$(( root_start + root_bytes / sector - 1 ))

# ── 4 · show the plan and get a real "yes" ─────────────────────────────────
echo
red  "  I30LTZ RECOVERY OS · install plan"
echo "  image : $(basename "$dir")"
echo "  disk  : $disk · $size_h · ${model:-?} · ${tran:-?}"
echo
echo "  KEPT exactly as-is:"
lsblk -po NAME,SIZE,FSTYPE,LABEL "$disk" | sed 's/^/    /'
[[ $new_table == 1 ]] && yel "  (empty disk: a new GPT partition table will be created)"
echo
echo "  ADDED in free space:"
printf '    %-12s %8s  %s\n' "I30LTZ-ESP" "$(numfmt --to=iec $esp_bytes)" "EFI boot partition"
printf '    %-12s %8s  %s\n' "i30ltz-root" "$(numfmt --to=iec $root_bytes)" "I30LTZ Recovery OS"
echo
if [[ $dry == 1 ]]; then grn "  dry run — nothing was written."; exit 0; fi
want=$(basename "$disk")
read -r -p "  Type the disk name ($want) to install, anything else cancels: " ans
[[ "$ans" == "$want" ]] || { yel "  cancelled — nothing was written."; exit 0; }

# ── 5 · partition (new table only if the disk was empty) ───────────────────
before=$(lsblk -lnpo NAME "$disk" | tail -n +2 | sort)
[[ $new_table == 1 ]] && sgdisk -o "$disk" >/dev/null
sgdisk -n "0:${esp_start}:${esp_end}" -t "0:${ESP_TYPE}" -c 0:I30LTZ-ESP "$disk" >/dev/null
sgdisk -n "0:${root_start}:${root_end}" -t "0:${ROOT_TYPE}" -c 0:i30ltz-root "$disk" >/dev/null
partprobe "$disk" 2>/dev/null || partx -u "$disk" 2>/dev/null || true
udevadm settle
after=$(lsblk -lnpo NAME "$disk" | tail -n +2 | sort)
mapfile -t added < <(comm -13 <(echo "$before") <(echo "$after"))
((${#added[@]} == 2)) || die "expected 2 new partitions, found ${#added[@]} — stopping before writing data"
esp_dev=""; root_dev=""
for p in "${added[@]}"; do
  case "$(lsblk -dno PARTLABEL "$p")" in I30LTZ-ESP) esp_dev=$p ;; i30ltz-root) root_dev=$p ;; esac
done
[[ -n "$esp_dev" && -n "$root_dev" ]] || die "could not identify the new partitions — stopping before writing data"

# ── 6 · copy the OS into ONLY the two new partitions ───────────────────────
yel "writing boot partition → $esp_dev"
dd if="$esp_img" of="$esp_dev" bs=4M conv=fsync status=progress
yel "writing OS → $root_dev"
dd if="$root_img" of="$root_dev" bs=4M conv=fsync status=progress
yel "growing the OS filesystem to fill its partition…"
e2fsck -fy "$root_dev" >/dev/null || true
tune2fs -U random "$root_dev" >/dev/null
resize2fs "$root_dev" >/dev/null
sync

echo
grn "  ✅ I30LTZ Recovery OS installed on $disk"
lsblk -po NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$disk" | sed 's/^/    /'
echo
yel "  boot it: plug into the X13 → power on → F12 → pick the USB drive"
yel "  first boot asks for your password, timezone and Wi-Fi."
