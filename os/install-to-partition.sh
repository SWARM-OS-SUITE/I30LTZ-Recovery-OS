#!/usr/bin/env bash
# =============================================================================
# I30LTZ Recovery OS — install INTO one existing partition (shared drive)
# v0.1.0 · 2026-10-01
#
#   sudo bash install-to-partition.sh <out/vX_DATE dir> /dev/sda5 --dry-run
#   sudo bash install-to-partition.sh <out/vX_DATE dir> /dev/sda5
#
# For a drive that already holds other things (e.g. the Crucial X9 with the
# Ubuntu build machine, backups and a spare "i30ltz-recovery" partition).
# What it does:
#   1. erases ONLY the partition you name and puts I30LTZ Recovery OS in it
#   2. adds its boot files to the drive's existing EFI partition in their own
#      folders (EFI/i30ltz, EFI/Linux) — Ubuntu's files are never touched
#   3. adds "I30LTZ Recovery OS" to the firmware boot menu (F12), AFTER the
#      current default, so your normal boot doesn't change
# Every other partition is left exactly as it is.
#
# It refuses when the partition:
#   • is on the internal NVMe (SWARM_OS's drive)
#   • is mounted, or is the running system's root
#   • is smaller than the OS image
#   • sits on a drive that already has another OS-root-typed partition
# =============================================================================
set -Eeuo pipefail
ROOT_TYPE=4f68bce3-e8cd-4db1-96e7-fbcaf984b709   # GPT "Linux root (x86-64)"
ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
LABEL="I30LTZ Recovery OS"

red() { printf '\033[1;31m%s\033[0m\n' "$*"; }
yel() { printf '\033[1;33m%s\033[0m\n' "$*"; }
grn() { printf '\033[1;32m%s\033[0m\n' "$*"; }
die() { red "✋ $*"; exit 1; }
part_field() { blkid -p -o value -s "$2" "$1" 2>/dev/null || true; }

dir="" part="" esp="" dry=0 nvram=1 allow_non_usb=0
while (($#)); do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --esp) esp="${2:?}"; shift 2 ;;
    --no-boot-entry) nvram=0; shift ;;                  # add the F12 entry yourself later
    --i-know-its-not-usb) allow_non_usb=1; shift ;;    # loop-device tests only
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) if [[ -z "$dir" ]]; then dir="$1"; elif [[ -z "$part" ]]; then part="$1"; else die "unexpected: $1"; fi; shift ;;
  esac
done
[[ -n "$dir" && -n "$part" ]] || { sed -n '5,6p' "$0"; exit 1; }
[[ $EUID -eq 0 ]] || die "run as root: sudo bash $0 …"
for c in sgdisk blkid e2fsck resize2fs tune2fs findmnt numfmt; do
  command -v "$c" >/dev/null || die "missing tool '$c' — install with: sudo apt install gdisk e2fsprogs"
done

# ── 1 · the image ──────────────────────────────────────────────────────────
esp_img=$(ls "$dir"/*.esp.raw 2>/dev/null | head -1 || true)
root_img=$(ls "$dir"/*.root-x86-64.raw 2>/dev/null | head -1 || true)
[[ -f "$esp_img" && -f "$root_img" ]] || die "no split ESP/root images in $dir — build with os/build.sh first"
yel "verifying image checksums…"
( cd "$dir" && sha256sum --quiet -c SHA256SUMS ) || die "checksum mismatch — rebuild the image"
root_img_bytes=$(stat -c %s "$root_img")

# ── 2 · the target partition ───────────────────────────────────────────────
[[ -b "$part" ]] || die "$part is not a block device"
[[ "$(lsblk -dno TYPE "$part")" == part ]] || die "$part is not a partition (give e.g. /dev/sda5)"
disk="/dev/$(lsblk -dno PKNAME "$part")"
partnum=$(cat "/sys/class/block/$(basename "$part")/partition")
[[ "$disk" == /dev/nvme* ]] && die "$part is on the internal NVMe — that's SWARM_OS's drive. Refusing."
tran=$(lsblk -dno TRAN "$disk" | xargs || true)
[[ "$tran" == usb || $allow_non_usb == 1 ]] || die "$disk is not USB-attached (transport: ${tran:-unknown}). Recovery OS belongs on an external drive."
findmnt -rno TARGET -S "$part" >/dev/null 2>&1 && die "$part is mounted ($(findmnt -rno TARGET -S "$part" | head -1)) — unmount it first"
[[ "$(readlink -f "$(findmnt -no SOURCE /)")" == "$(readlink -f "$part")" ]] && die "$part is the running system's root"
part_bytes=$(blockdev --getsize64 "$part")
(( part_bytes >= root_img_bytes )) || die "$part is $(numfmt --to=iec "$part_bytes") — the OS needs at least $(numfmt --to=iec "$root_img_bytes")"
while read -r p; do
  [[ "$p" == "$part" ]] && continue
  [[ "$(part_field "$p" PART_ENTRY_TYPE)" == "$ROOT_TYPE" ]] && \
    die "$p on the same drive is already typed as an OS root — two would confuse boot. Stopping."
done < <(lsblk -lnpo NAME,TYPE "$disk" | awk '$2=="part"{print $1}')

# ── 3 · the drive's EFI partition (shared, only ADDED to) ──────────────────
if [[ -z "$esp" ]]; then
  mapfile -t esps < <(lsblk -lnpo NAME,TYPE "$disk" | awk '$2=="part"{print $1}' | while read -r p; do
    [[ "$(part_field "$p" PART_ENTRY_TYPE)" == "$ESP_TYPE" ]] && echo "$p"; done)
  ((${#esps[@]} == 1)) || die "found ${#esps[@]} EFI partitions on $disk — pick one with --esp /dev/sdXN"
  esp=${esps[0]}
fi
esp_mnt=$(findmnt -rno TARGET -S "$esp" | head -1 || true)
tmp_esp=""
if [[ -z "$esp_mnt" ]]; then tmp_esp=$(mktemp -d); mount "$esp" "$tmp_esp"; esp_mnt=$tmp_esp; fi
img_mnt=$(mktemp -d); mount -o ro,loop "$esp_img" "$img_mnt"
cleanup() { umount "$img_mnt" 2>/dev/null || true; rmdir "$img_mnt" 2>/dev/null || true
            [[ -n "$tmp_esp" ]] && { umount "$tmp_esp" 2>/dev/null || true; rmdir "$tmp_esp" 2>/dev/null || true; }; }
trap cleanup EXIT
uki=$(ls "$img_mnt"/EFI/Linux/*.efi | head -1)
sdboot="$img_mnt/EFI/systemd/systemd-bootx64.efi"
[[ -f "$uki" && -f "$sdboot" ]] || die "boot files missing inside $esp_img"
need=$(( $(stat -c %s "$uki") + $(stat -c %s "$sdboot") + 4*1048576 ))
have=$(( $(df -B1 --output=avail "$esp_mnt" | tail -1) ))
(( have >= need )) || die "EFI partition $esp has $(numfmt --to=iec $have) free — needs $(numfmt --to=iec $need)"
loader_conf_exists=0; [[ -f "$esp_mnt/loader/loader.conf" ]] && loader_conf_exists=1

# ── 4 · plan + a real "yes" ────────────────────────────────────────────────
label_now=$(part_field "$part" LABEL); fs_now=$(part_field "$part" TYPE)
echo
red  "  I30LTZ RECOVERY OS · install into one partition"
echo "  image     : $(basename "$dir")"
echo "  drive     : $disk · $(lsblk -dno SIZE "$disk" | xargs) · $(lsblk -dno MODEL "$disk" | xargs) · ${tran:-?}"
echo
echo "  ERASED and replaced with the OS:"
echo "    $part   $(numfmt --to=iec "$part_bytes")   ${fs_now:-?}  label '${label_now:-none}'"
echo
echo "  ADDED to EFI partition $esp (mounted at $esp_mnt) — nothing there is changed or removed:"
echo "    EFI/i30ltz/systemd-bootx64.efi"
echo "    EFI/Linux/$(basename "$uki")"
[[ $loader_conf_exists == 0 ]] && echo "    loader/loader.conf" || echo "    (loader/loader.conf already exists — left as is)"
[[ $nvram == 1 ]] && echo "  ADDED to the F12 boot menu: \"$LABEL\" (after your current default)"
echo
echo "  KEPT exactly as-is:"
lsblk -lnpo NAME,SIZE,FSTYPE,LABEL "$disk" | awk -v p="$part" -v e="$esp" '$1!=p && $1!=e' | tail -n +2 | sed 's/^/    /'
echo
if [[ $dry == 1 ]]; then grn "  dry run — nothing was written."; exit 0; fi
want=$(basename "$part")
read -r -p "  Type the partition name ($want) to ERASE it and install, anything else cancels: " ans
[[ "$ans" == "$want" ]] || { yel "  cancelled — nothing was written."; exit 0; }

# ── 5 · write the OS into the one partition ────────────────────────────────
sgdisk -t "${partnum}:${ROOT_TYPE}" -c "${partnum}:i30ltz-root" "$disk" >/dev/null
yel "writing OS → $part"
dd if="$root_img" of="$part" bs=4M conv=fsync status=progress
e2fsck -fy "$part" >/dev/null || true
tune2fs -U random -L i30ltz-root "$part" >/dev/null
resize2fs "$part" >/dev/null

# ── 6 · boot files: add, never replace Ubuntu's ────────────────────────────
install -D -m 0644 "$sdboot" "$esp_mnt/EFI/i30ltz/systemd-bootx64.efi"
install -D -m 0644 "$uki" "$esp_mnt/EFI/Linux/$(basename "$uki")"
if [[ $loader_conf_exists == 0 ]]; then
  install -D -m 0644 "$img_mnt/loader/loader.conf" "$esp_mnt/loader/loader.conf"
fi
sync

# ── 7 · F12 boot menu entry (appended, default unchanged) ──────────────────
if [[ $nvram == 1 ]]; then
  if command -v efibootmgr >/dev/null && [[ -d /sys/firmware/efi/efivars ]]; then
    old_order=$(efibootmgr | sed -n 's/^BootOrder: //p')
    efibootmgr -q -c -d "$disk" -p "$(cat "/sys/class/block/$(basename "$esp")/partition")" \
      -L "$LABEL" -l '\EFI\i30ltz\systemd-bootx64.efi'
    new_num=$(efibootmgr | grep -F "$LABEL" | tail -1 | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p')
    [[ -n "$old_order" && -n "$new_num" ]] && efibootmgr -q -o "${old_order},${new_num}"
    grn "  F12 menu: \"$LABEL\" added (Boot$new_num), your default boot is unchanged"
  else
    yel "  couldn't reach the firmware boot menu from here — add it later with:"
    yel "  sudo efibootmgr -c -d $disk -p <esp-number> -L \"$LABEL\" -l '\\EFI\\i30ltz\\systemd-bootx64.efi'"
  fi
fi

echo
grn "  ✅ I30LTZ Recovery OS installed in $part"
lsblk -po NAME,SIZE,FSTYPE,LABEL "$disk" | sed 's/^/    /'
echo
yel "  boot it: restart → F12 → \"$LABEL\"   (Secure Boot must be OFF for v0.1)"
yel "  first boot asks for your password, timezone and Wi-Fi."
