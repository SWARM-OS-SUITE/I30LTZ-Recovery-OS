#!/usr/bin/env bash
# Make the firmware's "I30LTZ Recovery OS" boot entry start the Microsoft-signed SHIM instead of Debian's GRUB, so the
# entry still works when Secure Boot is turned ON. (Debian's GRUB is signed with Debian's key, which the firmware does not
# know; only the shim next to it, which carries that key, may be started by the firmware.)
#
#   sudo 70-scripts/repoint_recovery_boot_entry.sh            show what it would do (changes nothing)
#   sudo 70-scripts/repoint_recovery_boot_entry.sh --apply    do it
#
# Safe by construction: the new entry is created BEFORE the old one is removed, takes the old one's place in BootOrder, and
# nothing else in the firmware is touched. Re-running when it is already right does nothing.
# Testing: EFIBOOTMGR=/path/to/stub replaces the real efibootmgr.
set -euo pipefail
export PATH=/usr/sbin:/sbin:$PATH
LABEL="I30LTZ Recovery OS"
ESP_UUID="A367-87E3"      # the Recovery OS EFI partition (T7, sda1) - looked up by UUID, never by /dev/sdX
BOOTLOADER_ID="i30ltz"
EFIBOOTMGR=${EFIBOOTMGR:-efibootmgr}
APPLY=0
case "${1:-}" in "") ;; --apply) APPLY=1 ;; -h|--help) sed -n '2,12p' "$0"; exit 0 ;; *) echo "unknown option: $1" >&2; exit 2 ;; esac

say() { printf '%s\n' "$*"; }
die() { printf 'ABORT: %s\n' "$*" >&2; exit 1; }
run() { if (( APPLY )); then "$@"; else say "[dry-run] $*"; fi; }

[[ -d /sys/firmware/efi ]] || die "this machine was not booted via UEFI"
command -v "$EFIBOOTMGR" >/dev/null || die "efibootmgr is not installed"
(( ! APPLY )) || [[ $EUID -eq 0 || -n ${ESP_ROOT_OVERRIDE:-} ]] || die "needs root: sudo $0 --apply"   # (the override is a test hook; real efibootmgr still needs root)

# 1) the current entry
entries=$("$EFIBOOTMGR" -v)
cur_num="" cur_file=""
while IFS= read -r line; do
  if [[ $line =~ ^Boot([0-9A-Fa-f]{4})\*?[[:space:]]+"$LABEL"[[:space:]] ]]; then
    cur_num=${BASH_REMATCH[1]}
    [[ $line =~ File\(([^\)]*)\) ]] && cur_file=${BASH_REMATCH[1]}
    break
  fi
done <<< "$entries"
[[ -n $cur_num ]] || die "no firmware entry named '$LABEL' (the fallback \\EFI\\BOOT\\BOOTX64.EFI still boots the disk from the F12 menu)"
say "current entry: Boot$cur_num '$LABEL' -> $cur_file"
base=${cur_file##*\\}
if [[ ${base,,} == shimx64.efi ]]; then
  say "already starts the shim: nothing to do."
  exit 0
fi

# 2) the shim must really be on that EFI partition
tmp=""
if [[ -n ${ESP_ROOT_OVERRIDE:-} ]]; then      # test hook: a directory standing in for the mounted EFI partition
  mp=$ESP_ROOT_OVERRIDE; dev=/dev/test; disk=${DISK_OVERRIDE:-/dev/test}; part=${PART_OVERRIDE:-1}
else
  dev=$(blkid -U "$ESP_UUID" 2>/dev/null || true)
  [[ -n $dev ]] || die "EFI partition $ESP_UUID is not attached (plug in the Recovery OS disk) or blkid needs root"
  mp=$(findmnt -rn -S "$dev" -o TARGET 2>/dev/null | head -1 || true)
  if [[ -z $mp ]]; then
    [[ $EUID -eq 0 ]] || die "cannot look inside the EFI partition without root: run with sudo"
    tmp=$(mktemp -d); mount -o ro,noexec,nosuid,nodev "$dev" "$tmp"; mp=$tmp
  fi
  disk=/dev/$(lsblk -ndo PKNAME "$dev")
  part=$(cat "/sys/class/block/$(basename "$dev")/partition")
fi
trap '[[ -n $tmp ]] && { umount "$tmp" 2>/dev/null || true; rmdir "$tmp" 2>/dev/null || true; }' EXIT
[[ -f $mp/EFI/$BOOTLOADER_ID/shimx64.efi ]] || die "no EFI/$BOOTLOADER_ID/shimx64.efi on that EFI partition: Recovery OS was not installed with Debian's shim-signed, so there is nothing to point at"
say "found $mp/EFI/$BOOTLOADER_ID/shimx64.efi"

# 3) create the new entry, then swap it into the old one's BootOrder slot, then remove the old one
order=$(sed -n 's/^BootOrder: //p' <<< "$entries")
say "BootOrder now: $order"
run "$EFIBOOTMGR" -c -d "$disk" -p "$part" -L "$LABEL" -l "\\EFI\\$BOOTLOADER_ID\\shimx64.efi"
if (( APPLY )); then
  new_num=""
  while IFS= read -r line; do
    if [[ $line =~ ^Boot([0-9A-Fa-f]{4})\*?[[:space:]]+"$LABEL"[[:space:]].*[Ss][Hh][Ii][Mm]x64\.efi ]]; then new_num=${BASH_REMATCH[1]}; fi
  done < <("$EFIBOOTMGR" -v)
  [[ -n $new_num && $new_num != "$cur_num" ]] || die "the new entry was not created; the old one is untouched"
  # keep the new entry exactly where the old one was (efibootmgr puts a new entry first by default)
  new_order=$(tr ',' '\n' <<< "$order" | awk -v o="$cur_num" -v n="$new_num" '$0==o{print n; next} $0!=n{print}' | paste -sd, -)
  "$EFIBOOTMGR" -o "$new_order" >/dev/null
  "$EFIBOOTMGR" -b "$cur_num" -B >/dev/null
  say "done: Boot$new_num '$LABEL' -> \\EFI\\$BOOTLOADER_ID\\shimx64.efi ; Boot$cur_num removed ; BootOrder $new_order"
else
  say "[dry-run] then: put the new entry where Boot$cur_num is in BootOrder, and remove Boot$cur_num"
  say "Nothing was changed. Run with --apply to do it."
fi
