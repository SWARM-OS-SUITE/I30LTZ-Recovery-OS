#!/usr/bin/env bash
# =============================================================================
# I30LTZ Recovery OS — install INTO one existing partition, chosen by UUID
# v0.1.1 · 2026-10-01
#
#   lsblk -o NAME,SIZE,LABEL,PARTUUID /dev/sda          # find the PARTUUID
#   sudo bash install-to-partition.sh <out/vX_DATE dir> PARTUUID=<uuid> --dry-run
#   sudo bash install-to-partition.sh <out/vX_DATE dir> PARTUUID=<uuid>
#
# For a drive that already holds other things (e.g. the Crucial X9 with the
# Ubuntu build machine, backups and a spare "i30ltz-recovery" partition).
#
# What it changes — and nothing else:
#   1. the ONE partition you name (by PARTUUID): its contents become the OS
#   2. the drive's EFI partition: files are ADDED in their own places
#        EFI/i30ltz/…, loader/entries/i30ltz-recovery-os.conf
#      Ubuntu's boot files are never modified or removed
#   3. the F12 firmware menu: "I30LTZ Recovery OS" appended after your default
# The partition table is NOT rewritten. Other partitions are never written.
# The OS boots with root=PARTUUID=…, so drive names (sda/sdb) don't matter.
#
# It refuses when the partition is on the internal NVMe, is mounted, is the
# running system's root, or is smaller than the OS image.
# =============================================================================
set -Eeuo pipefail
LABEL="I30LTZ Recovery OS"
ENTRY="i30ltz-recovery-os.conf"

red() { printf '\033[1;31m%s\033[0m\n' "$*"; }
yel() { printf '\033[1;33m%s\033[0m\n' "$*"; }
grn() { printf '\033[1;32m%s\033[0m\n' "$*"; }
die() { red "✋ $*"; exit 1; }
part_field() { blkid -p -o value -s "$2" "$1" 2>/dev/null || true; }   # reads the disk, not udev
by_uuid() {   # PARTUUID=… | UUID=… | /dev/… → device path
  case "$1" in
    PARTUUID=*|UUID=*) blkid -t "$1" -o device 2>/dev/null | head -1 || true ;;
    /dev/*) echo "$1" ;;
    *) blkid -t "PARTUUID=$1" -o device 2>/dev/null | head -1 || true ;;
  esac
}

dir="" target="" esp_arg="" dry=0 nvram=1 allow_non_usb=0
while (($#)); do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --esp) esp_arg="${2:?}"; shift 2 ;;
    --no-boot-entry) nvram=0; shift ;;                  # add the F12 entry yourself later
    --i-know-its-not-usb) allow_non_usb=1; shift ;;    # loop-device tests only
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) if [[ -z "$dir" ]]; then dir="$1"; elif [[ -z "$target" ]]; then target="$1"; else die "unexpected: $1"; fi; shift ;;
  esac
done
[[ -n "$dir" && -n "$target" ]] || { sed -n '5,7p' "$0"; exit 1; }
[[ $EUID -eq 0 ]] || die "run as root: sudo bash $0 …"
for c in blkid e2fsck resize2fs tune2fs findmnt numfmt mcopy mdir python3; do
  command -v "$c" >/dev/null || die "missing tool '$c' — install with: sudo apt install e2fsprogs mtools python3"
done

# ── 1 · the image ──────────────────────────────────────────────────────────
esp_img=$(ls "$dir"/*.esp.raw 2>/dev/null | head -1 || true)
root_img=$(ls "$dir"/*.root-x86-64.raw 2>/dev/null | head -1 || true)
[[ -f "$esp_img" && -f "$root_img" ]] || die "no split ESP/root images in $dir — build with os/build.sh first"
yel "verifying image checksums…"
( cd "$dir" && sha256sum --quiet -c SHA256SUMS ) || die "checksum mismatch — rebuild the image"
root_img_bytes=$(stat -c %s "$root_img")
uki_src=$(mdir -i "$esp_img" -b ::/EFI/Linux 2>/dev/null | grep -i '\.efi$' | head -1)
[[ -n "$uki_src" ]] || die "no kernel image (UKI) inside $esp_img"
uki_name=$(basename "$uki_src")
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mcopy -o -i "$esp_img" "$uki_src" "$work/$uki_name"
mcopy -o -i "$esp_img" ::/EFI/systemd/systemd-bootx64.efi "$work/systemd-bootx64.efi"
# the UKI's built-in kernel command line + name, so our loader entry matches it exactly
read_pe() { python3 - "$1" "$2" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read(); want=sys.argv[2]
pe=struct.unpack_from('<I',d,0x3c)[0]; n=struct.unpack_from('<H',d,pe+6)[0]; o=pe+24+struct.unpack_from('<H',d,pe+20)[0]
for _ in range(n):
    name=d[o:o+8].rstrip(b'\0').decode(); vs,va,rs,rp=struct.unpack_from('<IIII',d,o+8)
    if name==want: print(d[rp:rp+vs].rstrip(b'\0').decode().strip())
    o+=40
PY
}
cmdline=$(read_pe "$work/$uki_name" .cmdline)
pretty=$(read_pe "$work/$uki_name" .osrel | sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p')
[[ -n "$cmdline" ]] || die "couldn't read the kernel command line from the UKI"

# ── 2 · the target partition (by UUID) ─────────────────────────────────────
part=$(by_uuid "$target")
[[ -n "$part" && -b "$part" ]] || die "no partition found for '$target' — list them with: lsblk -o NAME,SIZE,LABEL,PARTUUID"
[[ "$(lsblk -dno TYPE "$part")" == part ]] || die "$target is not a partition"
partuuid=$(part_field "$part" PART_ENTRY_UUID)
[[ -n "$partuuid" ]] || die "$part has no PARTUUID (needs a GPT drive)"
disk="/dev/$(lsblk -dno PKNAME "$part")"
[[ "$disk" == /dev/nvme* ]] && die "$target is on the internal NVMe — that's SWARM_OS's drive. Refusing."
tran=$(lsblk -dno TRAN "$disk" | xargs || true)
[[ "$tran" == usb || $allow_non_usb == 1 ]] || die "$disk is not USB-attached (transport: ${tran:-unknown}). Recovery OS belongs on an external drive."
findmnt -rno TARGET -S "$part" >/dev/null 2>&1 && die "$part is mounted ($(findmnt -rno TARGET -S "$part" | head -1)) — unmount it first"
root_dev=$(findmnt -no SOURCE / | sed 's/\[.*//')          # btrfs shows /dev/sda2[/@]
[[ "$(readlink -f "$root_dev")" == "$(readlink -f "$part")" ]] && die "$part is the running system's root"
part_bytes=$(blockdev --getsize64 "$part")
(( part_bytes >= root_img_bytes )) || die "$part is $(numfmt --to=iec "$part_bytes") — the OS needs at least $(numfmt --to=iec "$root_img_bytes")"

# ── 3 · the drive's EFI partition (only ADDED to) ──────────────────────────
ESP_TYPE=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
if [[ -n "$esp_arg" ]]; then
  esp=$(by_uuid "$esp_arg"); [[ -b "$esp" ]] || die "no EFI partition found for '$esp_arg'"
else
  mapfile -t esps < <(lsblk -lnpo NAME,TYPE "$disk" | awk '$2=="part"{print $1}' | while read -r p; do
    [[ "$(part_field "$p" PART_ENTRY_TYPE)" == "$ESP_TYPE" ]] && echo "$p"; done)
  ((${#esps[@]} == 1)) || die "found ${#esps[@]} EFI partitions on $disk — pick one with --esp PARTUUID=…"
  esp=${esps[0]}
fi
esp_partuuid=$(part_field "$esp" PART_ENTRY_UUID)
esp_mnt=$(findmnt -rno TARGET -S "$esp" | head -1 || true)
esp_has() { if [[ -n "$esp_mnt" ]]; then [[ -e "$esp_mnt/$1" ]]; else mdir -i "$esp" "::/$1" >/dev/null 2>&1; fi; }
need=$(( $(stat -c %s "$work/$uki_name") + $(stat -c %s "$work/systemd-bootx64.efi") + 4*1048576 ))
if [[ -n "$esp_mnt" ]]; then have=$(df -B1 --output=avail "$esp_mnt" | tail -1 | tr -dc '0-9')
else have=$(mdir -i "$esp" ::/ 2>/dev/null | grep 'bytes free' | tr -dc '0-9'); fi   # "1 070 000 000 bytes free"
(( ${have:-0} >= need )) || die "EFI partition $esp has $(numfmt --to=iec "${have:-0}") free — needs $(numfmt --to=iec $need)"
loader_conf_exists=0; esp_has loader/loader.conf && loader_conf_exists=1

# ── 4 · plan + a real "yes" ────────────────────────────────────────────────
echo
red  "  I30LTZ RECOVERY OS · install into one partition (by UUID)"
echo "  image : $(basename "$dir") · ${pretty:-?}"
echo "  drive : $disk · $(lsblk -dno SIZE "$disk" | xargs) · $(lsblk -dno MODEL "$disk" | xargs) · ${tran:-?}"
echo
echo "  ERASED and replaced with the OS (the only partition written):"
echo "    PARTUUID=$partuuid   (now $part · $(numfmt --to=iec "$part_bytes") · $(part_field "$part" TYPE) · label '$(part_field "$part" LABEL)')"
echo
echo "  ADDED to EFI partition PARTUUID=$esp_partuuid (now $esp) — nothing there is changed or removed:"
echo "    EFI/i30ltz/systemd-bootx64.efi"
echo "    EFI/i30ltz/$uki_name"
echo "    loader/entries/$ENTRY   → root=PARTUUID=$partuuid"
[[ $loader_conf_exists == 0 ]] && echo "    loader/loader.conf" || echo "    (loader/loader.conf already exists — left as is)"
[[ $nvram == 1 ]] && echo "  ADDED to the F12 boot menu: \"$LABEL\" (after your current default)"
echo
echo "  NOT touched: the partition table and every other partition:"
lsblk -lnpo NAME,SIZE,FSTYPE,LABEL "$disk" | awk -v p="$part" '$1!=p' | tail -n +2 | sed 's/^/    /'
echo
if [[ $dry == 1 ]]; then grn "  dry run — nothing was written."; exit 0; fi
want=${partuuid:0:8}
read -r -p "  Type the first 8 characters of the PARTUUID ($want) to ERASE it and install: " ans
[[ "$ans" == "$want" ]] || { yel "  cancelled — nothing was written."; exit 0; }

# ── 5 · write the OS into the one partition ────────────────────────────────
yel "writing OS → PARTUUID=$partuuid ($part)"
dd if="$root_img" of="$part" bs=4M conv=fsync status=progress
e2fsck -fy "$part" >/dev/null || true
tune2fs -U random -L i30ltz-root "$part" >/dev/null
resize2fs "$part" >/dev/null

# ── 6 · boot files: add, never replace ─────────────────────────────────────
cat > "$work/$ENTRY" <<EOF
# I30LTZ Recovery OS — boot entry (installed $(date +%F)); root found by PARTUUID
title   ${pretty:-I30LTZ Recovery OS}
efi     /EFI/i30ltz/$uki_name
options root=PARTUUID=$partuuid $cmdline
EOF
if [[ $loader_conf_exists == 0 ]]; then
  printf '# I30LTZ Recovery OS\ndefault %s\ntimeout 3\neditor no\nconsole-mode max\n' "$ENTRY" > "$work/loader.conf"
fi
if [[ -n "$esp_mnt" ]]; then
  install -D -m 0644 "$work/systemd-bootx64.efi" "$esp_mnt/EFI/i30ltz/systemd-bootx64.efi"
  install -D -m 0644 "$work/$uki_name"           "$esp_mnt/EFI/i30ltz/$uki_name"
  install -D -m 0644 "$work/$ENTRY"              "$esp_mnt/loader/entries/$ENTRY"
  [[ $loader_conf_exists == 0 ]] && install -D -m 0644 "$work/loader.conf" "$esp_mnt/loader/loader.conf"
else
  for d in ::/EFI ::/EFI/i30ltz ::/loader ::/loader/entries; do mmd -i "$esp" "$d" 2>/dev/null || true; done
  mcopy -o -i "$esp" "$work/systemd-bootx64.efi" ::/EFI/i30ltz/systemd-bootx64.efi
  mcopy -o -i "$esp" "$work/$uki_name"           "::/EFI/i30ltz/$uki_name"
  mcopy -o -i "$esp" "$work/$ENTRY"              "::/loader/entries/$ENTRY"
  [[ $loader_conf_exists == 0 ]] && mcopy -o -i "$esp" "$work/loader.conf" ::/loader/loader.conf
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
    grn "  F12 menu: \"$LABEL\" added (Boot$new_num) — your default boot is unchanged"
  else
    yel "  couldn't reach the firmware boot menu from here — add it later with:"
    yel "  sudo efibootmgr -c -d $disk -p <esp-number> -L \"$LABEL\" -l '\\EFI\\i30ltz\\systemd-bootx64.efi'"
  fi
fi

echo
grn "  ✅ I30LTZ Recovery OS installed in PARTUUID=$partuuid"
echo
yel "  boot it: restart → F12 → \"$LABEL\"   (Secure Boot must be OFF for v0.1)"
yel "  first boot asks for your password, timezone and Wi-Fi."
