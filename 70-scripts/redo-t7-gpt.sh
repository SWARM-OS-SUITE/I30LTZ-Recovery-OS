#!/usr/bin/env bash
# Re-make the Samsung T7 as GPT with the SAME sizes as the 2026-10-10 layout.
# User, 2026-10-10: the first layout was MBR ("dos"), which was a mistake. See MASTER_BUILD_LIST.md RC-22.
#
#   redo-t7-gpt.sh                plan only: finds the T7, shows what is on it now and what would be made.
#                                 Read-only, needs no root.
#   sudo redo-t7-gpt.sh --apply   ERASES the whole T7 (you must type a phrase first), writes a GPT table and the
#                                 four partitions, formats the first three. Nothing else is touched.
#
# New layout (512-byte sectors, MiB-aligned; sizes identical to before, 4 slots of 128 GPT entries):
#   1  EFI System  1000 MiB   vfat   label EFI           volume id 2D87-5490        (same as before)
#   2  Linux       453.1 GiB  btrfs  label "Recovery OS" UUID 96969ed2-...         (same as before) -> /mnt/recoveryos
#   3  Linux swap  6000 MiB   swap   label swap          UUID 9228d0e1-...         (same as before)
#   4  Linux       471.6 GiB  NOT formatted: reserved for a possible future OS. Never format it without the user.
# The old order had swap last; free is now last so it can later be grown, shrunk or split. Sizes are unchanged.
# Filesystem UUIDs are re-used on purpose, so mounts.manifest / fstab.canonical / MOUNTS.md stay correct.
#
# Safety: the disk is found by model "PSSD T7" + exact size (never by /dev/sdX: letters change between boots).
# It refuses unless exactly one disk matches, nothing on it is mounted, and none of it is swap in use.
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

T7_MODEL="PSSD T7"
T7_BYTES=1000204886016            # 931.5 GiB, as lsblk -b reports it
CONFIRM_PHRASE="ERASE T7"

ESP_START=2048;        ESP_SECTORS=2048000        # 1000 MiB
ROOT_START=2050048;    ROOT_SECTORS=950231040     # 463980 MiB = 453.1 GiB
SWAP_START=952281088;  SWAP_SECTORS=12288000      # 6000 MiB
FREE_START=964569088;  FREE_SECTORS=988954624     # 482888 MiB = 471.6 GiB; ends 1,953,523,711 < GPT backup area

ESP_VOLID=2D875490
ROOT_UUID=96969ed2-15b1-48e6-815e-20fa87d1fb5b
SWAP_UUID=9228d0e1-79d0-41ff-ba1d-dd57af5c2d0d

die()  { echo "STOP: $*" >&2; exit 1; }
say()  { echo "== $*"; }
run()  { echo "+ $*"; "$@"; }

layout_script() {   # the sfdisk input; $1 = disk path (only used in the partition lines)
  cat <<EOF
label: gpt
unit: sectors
first-lba: 2048

$(part "$1" 1) : start=$ESP_START,  size=$ESP_SECTORS,  type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System Partition"
$(part "$1" 2) : start=$ROOT_START, size=$ROOT_SECTORS, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Recovery OS"
$(part "$1" 3) : start=$SWAP_START, size=$SWAP_SECTORS, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name="swap"
$(part "$1" 4) : start=$FREE_START, size=$FREE_SECTORS, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="FREE reserved for a future OS"
EOF
}

part() { [[ $1 =~ [0-9]$ ]] && echo "${1}p$2" || echo "${1}$2"; }

find_t7() {
  local n m found=()
  while read -r n; do
    [[ $(lsblk -dnb -o SIZE "$n") == "$T7_BYTES" ]] || continue
    m=$(lsblk -dn -o MODEL "$n" | sed 's/[[:space:]]*$//')
    [[ $m == "$T7_MODEL" ]] && found+=("$n")
  done < <(lsblk -dnpo NAME,TYPE | awk '$2=="disk"{print $1}')
  (( ${#found[@]} == 1 )) || die "expected exactly one \"$T7_MODEL\" of $T7_BYTES bytes, found ${#found[@]}. Is the T7 plugged in (and no second one)?"
  echo "${found[0]}"
}

main() {
  local apply=0
  [[ ${1:-} == --apply ]] && apply=1
  [[ $# -eq 0 || ${1:-} == --apply ]] || die "usage: $0 [--apply]"

  for t in sfdisk wipefs blockdev mkfs.btrfs mkfs.vfat mkswap udevadm lsblk; do
    command -v "$t" >/dev/null || die "missing tool: $t (apt install util-linux dosfstools btrfs-progs)"
  done

  local disk; disk=$(find_t7)
  say "found the T7 as $disk (this boot's letter; it will differ later)"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,UUID,PARTTYPENAME "$disk"

  say "partition table now: $(lsblk -dn -o PTTYPE "$disk")  ->  will become: gpt"
  say "plan (sectors of 512 B):"
  layout_script "$disk" | sed 's/^/    /'
  echo "    format: 1 vfat 'EFI' id $ESP_VOLID | 2 btrfs 'Recovery OS' $ROOT_UUID | 3 swap $SWAP_UUID | 4 left unformatted"

  [[ -z $(lsblk -rno MOUNTPOINTS "$disk" | tr -d '[:space:]') ]] || die "something on $disk is mounted; unmount it first (nothing was changed)"
  ! grep -q "^${disk}" /proc/swaps || die "swap on $disk is in use; swapoff it first (nothing was changed)"

  if (( ! apply )); then
    say "PLAN ONLY, nothing was changed. To do it:  sudo bash $0 --apply"
    return 0
  fi

  (( EUID == 0 )) || die "--apply needs root: run it with sudo (nothing was changed)"
  [[ -t 0 ]] || die "--apply asks for confirmation on the keyboard; run it from a terminal"
  echo
  echo "This ERASES everything on $disk ($T7_MODEL) and cannot be undone."
  read -rp "Type exactly \"$CONFIRM_PHRASE\" to continue: " ans
  [[ $ans == "$CONFIRM_PHRASE" ]] || die "phrase did not match; nothing was changed"

  local p
  say "clearing old signatures"
  for p in 1 2 3 4; do
    if [[ -b $(part "$disk" $p) ]]; then run wipefs -a "$(part "$disk" $p)"; fi
  done
  run wipefs -a "$disk"

  say "writing the GPT table"
  layout_script "$disk" | run sfdisk --wipe always --wipe-partitions always "$disk"
  run udevadm settle
  run blockdev --rereadpt "$disk" || true
  run udevadm settle
  for _ in $(seq 1 20); do [[ -b $(part "$disk" 4) ]] && break; sleep 0.5; done
  for p in 1 2 3 4; do [[ -b $(part "$disk" $p) ]] || die "partition $p did not appear; re-plug the T7 and run: lsblk $disk"; done

  say "formatting (partition 4 stays empty)"
  for p in 1 2 3; do run wipefs -a "$(part "$disk" $p)"; done
  run mkfs.vfat -F 32 -n EFI -i "$ESP_VOLID" "$(part "$disk" 1)"
  run mkfs.btrfs -f -L "Recovery OS" -U "$ROOT_UUID" "$(part "$disk" 2)"
  run mkswap -L swap -U "$SWAP_UUID" "$(part "$disk" 3)"
  run udevadm settle

  say "result"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,UUID,PARTTYPENAME "$disk"
  [[ $(lsblk -dn -o PTTYPE "$disk") == gpt ]] || die "table is not gpt after all; check by hand"
  say "done. Now tell Claude, or run: bash /mnt/recoverybuild/70-scripts/check-mounts.sh"
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
