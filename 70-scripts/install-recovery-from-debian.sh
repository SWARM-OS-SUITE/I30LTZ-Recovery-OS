#!/usr/bin/env bash
# Install I30LTZ Recovery OS from the Debian host onto the former CachyOS partition.
#
#   install-recovery-from-debian.sh                  preflight only (read-only, no root needed)
#   install-recovery-from-debian.sh --dry-run all    print every command of every stage, run nothing
#   sudo install-recovery-from-debian.sh format      ERASE the target partition, make btrfs + subvolumes
#   sudo install-recovery-from-debian.sh rootfs      unpack the ISO's root filesystem, write fstab
#   sudo install-recovery-from-debian.sh bootloader  initramfs + GRUB into the existing ESP (not formatted)
#   sudo install-recovery-from-debian.sh finish      set the root password, unmount everything
#   sudo install-recovery-from-debian.sh all         format, rootfs, bootloader, finish in one go
#   sudo install-recovery-from-debian.sh cleanup     unmount the install mount point (after a failed run)
#   options: --iso PATH   (default: newest i30ltz-recovery-*.iso in /mnt/ventoy/ISO/recovery-os)
#
# Decisions (user, 2026-10-07): Recovery OS root = former CachyOS partition, btrfs, beside the
# lucy-master LUKS volume; EFI = that disk's existing ESP. Partitions are found by GPT PARTUUID,
# never by /dev/sdX letter (letters swap between boots). The ESP is mounted, never formatted; only
# \EFI\i30ltz and the removable-media fallback \EFI\BOOT\BOOTX64.EFI are written to it. The
# lucy-master partition is never opened.
# STANDALONE (user, 2026-10-08): Recovery OS must boot with the Debian disk unplugged. It therefore
# gets its own complete bootloader on its own ESP - fallback path (so the firmware boot menu lists the
# disk by itself), the named \EFI\i30ltz loader, and a firmware boot entry appended to (never
# replacing) the boot order. Nothing in it points at Debian's GRUB, ESP or disk.
set -Eeuo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FSTAB_CANONICAL="$HERE/fstab.canonical"

ROOT_PARTUUID=92e15d58-ee1a-4893-9ecf-0225023d36e2      # Samsung T7 Recovery OS root (btrfs 453G sda2)
ESP_PARTUUID=952e4e99-72fc-4639-b751-5d8f25f7ed98       # Samsung T7 ESP (vfat 1000M sda1, fs UUID 2D87-5490)
ESP_FS_UUID=2D87-5490
PROTECT_PARTUUID=d5055a4e-6b80-463c-95a4-8f330fd9ca59   # Samsung T7 part 4: FREE reserved for future OS (never touched)
MNT=/mnt/recoveryos-install        # install-time mount point: NOT the Debian automount below
DEBIAN_MNT=/mnt/recoveryos         # Debian's x-systemd.automount line (UUID-pinned); stale after the format
AUTOMOUNT_UNIT=mnt-recoveryos.automount
ISO_DIR=/mnt/ventoy/ISO/recovery-os
BOOTLOADER_ID=i30ltz
MIN_ROOT_BYTES=$((20 * 1024 * 1024 * 1024))

DRY=0; ISO=""; STAGE=preflight
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --iso) ISO=${2:?--iso needs a path}; shift ;;
    -h|--help) sed -n 2,19p "$0"; exit 0 ;;
    preflight|format|rootfs|bootloader|finish|all|cleanup) STAGE=$1 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAILED=1; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
FAILED=0
FRESH=0; [[ $STAGE == preflight || $STAGE == format || $STAGE == all ]] && FRESH=1
run()  { if (( DRY )); then printf '+ %s\n' "$*"; else "$@"; fi; }
need_root() { (( DRY )) || [[ $EUID -eq 0 ]] || die "stage '$STAGE' needs root: sudo $0 $STAGE"; }
confirm() { # confirm "<what will happen>" <exact string to type>
  (( DRY )) && { say "[dry-run] would ask: type '$2'"; return 0; }
  say; say "$1"; read -r -p "Type exactly  $2  to continue (anything else aborts): " ans
  [[ $ans == "$2" ]] || die "confirmation did not match; nothing was changed."
}

# ---------------------------------------------------------------- identify devices
resolve() { readlink -f "/dev/disk/by-partuuid/$1" 2>/dev/null || true; }
TARGET=$(resolve "$ROOT_PARTUUID"); ESP=$(resolve "$ESP_PARTUUID"); PROTECT=$(resolve "$PROTECT_PARTUUID")

pick_iso() {
  if [[ -z $ISO ]]; then
    for d in "$ISO_DIR" /mnt/recoverybuild/10-releases /mnt/downloads/iso-from-ventoy-2026-10-13/recovery-os; do
      ISO=$(ls -1t "$d"/i30ltz-recovery-*.iso 2>/dev/null | head -1 || true)
      [[ -n $ISO ]] && break
    done
  fi
}

preflight() {
  say "== preflight (read-only) =="
  [[ -b $TARGET ]]  || fail "root partition PARTUUID $ROOT_PARTUUID not found"
  [[ -b $ESP ]]     || fail "ESP PARTUUID $ESP_PARTUUID not found"
  [[ -b $PROTECT ]] || fail "protected partition PARTUUID $PROTECT_PARTUUID not found (refusing to run blind)"
  if [[ -b $TARGET && -b $ESP && -b $PROTECT ]]; then
    [[ $TARGET != "$ESP" && $TARGET != "$PROTECT" && $ESP != "$PROTECT" ]] || fail "two of the three partitions resolve to one device"
    local td ed pd
    td=$(lsblk -ndo PKNAME "$TARGET"); ed=$(lsblk -ndo PKNAME "$ESP"); pd=$(lsblk -ndo PKNAME "$PROTECT")
    [[ $td == "$ed" && $td == "$pd" ]] || fail "root, ESP and protected part 4 are not all on one disk ($td/$ed/$pd)"
    say "root target : $TARGET  $(lsblk -ndo SIZE,FSTYPE,LABEL "$TARGET" | tr -s ' ')  (PARTUUID $ROOT_PARTUUID)"
    say "ESP (kept) : $ESP  $(lsblk -ndo SIZE,FSTYPE,UUID "$ESP" | tr -s ' ')"
    say "protected  : $PROTECT  (Samsung T7 free part 4, never touched)"
    local sz; sz=$(lsblk -bndo SIZE "$TARGET")
    (( sz >= MIN_ROOT_BYTES )) || fail "root partition is only $sz bytes (< 20 GiB)"
    [[ $(lsblk -ndo FSTYPE "$ESP") == vfat ]] || fail "ESP is not vfat"
    [[ $(lsblk -ndo UUID "$ESP") == "$ESP_FS_UUID" ]] || fail "ESP filesystem UUID is not $ESP_FS_UUID (wrong partition?)"
    if (( FRESH )); then
      local tm; tm=$(findmnt -rn -o TARGET -S "$TARGET" | head -1 || true)
      if [[ -z $tm ]]; then
        :
      elif [[ $tm != "$DEBIAN_MNT" ]]; then
        fail "$TARGET is mounted at $tm; unmount it first"
      elif [[ -n $(ls -A "$DEBIAN_MNT" 2>/dev/null) ]]; then
        fail "$TARGET is mounted at $DEBIAN_MNT and is NOT empty ($(ls -A "$DEBIAN_MNT" | head -3 | tr '\n' ' ')...); refusing to erase it"
      else
        say "note: $TARGET is mounted at $DEBIAN_MNT but empty; the format stage will stop the automount and unmount it"
      fi
    fi
    local rs; rs=$(findmnt -n -o SOURCE / | sed 's/\[.*//'); [[ $(readlink -f "$rs") != "$TARGET" ]] || fail "the running root is the target"
    if (( FRESH )); then
      findmnt -rn -S "$ESP" >/dev/null && say "note: ESP is currently mounted at $(findmnt -rn -o TARGET -S "$ESP" | head -1); unmount it before the bootloader stage"
    fi
  fi
  if (( FRESH )) && mountpoint -q "$MNT" 2>/dev/null; then fail "$MNT is already a mountpoint (run: sudo $0 cleanup)"; fi

  local t
  for t in mkfs.btrfs btrfs wipefs blkid unsquashfs grub-install mount chroot sha256sum 7z; do
    command -v "$t" >/dev/null || fail "missing tool: $t"
  done

  pick_iso
  if [[ -z $ISO || ! -f $ISO ]]; then
    fail "no Recovery ISO found (looked in $ISO_DIR; pass --iso PATH)"
  else
    say "ISO         : $ISO ($(du -h "$ISO" | cut -f1))"
    if [[ -f $ISO.sha256 ]]; then
      (cd "$(dirname "$ISO")" && sha256sum -c "$(basename "$ISO").sha256" >/dev/null 2>&1) \
        && say "ISO sha256  : OK" || fail "ISO sha256 does not match $(basename "$ISO").sha256"
    else
      fail "no $(basename "$ISO").sha256 next to the ISO"
    fi
    7z l "$ISO" 2>/dev/null | grep -q 'live/filesystem.squashfs' || fail "ISO has no live/filesystem.squashfs"
  fi

  if (( FAILED )); then say; say "PREFLIGHT FAILED - nothing was changed."; return 1; fi
  say; say "PREFLIGHT OK. Plan:"
  say "  1. format     ERASE $TARGET (currently: $(lsblk -ndo FSTYPE,LABEL "$TARGET" | tr -s ' ')) -> btrfs 'Recovery OS', subvolumes @ @home @snapshots"
  say "  2. rootfs     unpack live/filesystem.squashfs from the ISO into $MNT, write fstab (UUIDs)"
  say "  3. bootloader chroot: update-initramfs, grub-install into the ESP ($ESP, NOT formatted) as \\EFI\\$BOOTLOADER_ID AND the standalone fallback \\EFI\\BOOT\\BOOTX64.EFI (existing one is backed up), update-grub;"
  say "                then a firmware boot entry 'I30LTZ Recovery OS' appended AFTER the current boot order (Debian stays the default)"
  say "  4. finish     set the root password, unmount"
  say "STANDALONE: Recovery OS will boot from $ESP by itself (no Debian disk, GRUB or ESP involved). The ESP keeps its other files (e.g. \\EFI\\cachyos)."
  return 0
}

# ---------------------------------------------------------------- stages
mount_root() { # mount the @ subvolume of the target at $MNT
  run install -d "$MNT"
  run mount -o subvol=@,compress=zstd,noatime "$TARGET" "$MNT"
}

stage_format() {
  need_root
  confirm "This ERASES everything on $TARGET (currently $(lsblk -ndo SIZE,FSTYPE,LABEL "$TARGET" | tr -s ' ')) and makes a fresh btrfs 'Recovery OS'.
It does NOT touch $ESP or the lucy-master partition $PROTECT." "$TARGET"
  if (( DRY )) || findmnt -rn -S "$TARGET" >/dev/null; then
    (( DRY )) || [[ -z $(ls -A "$DEBIAN_MNT" 2>/dev/null) ]] || die "$DEBIAN_MNT is not empty; refusing to erase it"
    run systemctl stop "$AUTOMOUNT_UNIT" || true
    # stopping the automount unit usually unmounts the partition already; only umount if it is still mounted
    if (( DRY )) || findmnt -rn -S "$TARGET" >/dev/null; then run umount "$DEBIAN_MNT"; fi
  fi
  if (( ! DRY )) && findmnt -rn -S "$TARGET" >/dev/null; then
    die "$TARGET is still mounted at $(findmnt -rn -o TARGET -S "$TARGET" | head -1); not erasing"
  fi
  run udevadm settle
  run wipefs -a "$TARGET"
  run mkfs.btrfs -f -L "Recovery OS" "$TARGET"
  run install -d "$MNT"
  run mount -o compress=zstd,noatime "$TARGET" "$MNT"
  run btrfs subvolume create "$MNT/@"
  run btrfs subvolume create "$MNT/@home"
  run btrfs subvolume create "$MNT/@snapshots"
  run umount "$MNT"
  mount_root
  (( DRY )) || say "formatted. New root filesystem UUID: $(blkid -s UUID -o value "$TARGET")  <- record this in CLAUDE.md and the Recovery docs"
}

iso_squashfs_mount() { # echo the path of a loop-mounted ISO; caller unmounts
  if (( DRY )); then ISOMNT=/run/recovery-iso.DRYRUN; else ISOMNT=$(mktemp -d /run/recovery-iso.XXXXXX); fi
  run mount -o loop,ro "$ISO" "$ISOMNT"
}

stage_rootfs() {
  need_root
  pick_iso; [[ -f $ISO ]] || die "no ISO"
  if (( ! DRY )); then
    mountpoint -q "$MNT" || die "$MNT is not mounted (run the format stage first, or mount the @ subvolume there)"
    [[ $(findmnt -n -o SOURCE "$MNT" | sed 's/\[.*//') == "$TARGET" ]] || die "$MNT is not mounted from $TARGET"
    [[ -z $(ls -A "$MNT" 2>/dev/null | grep -v '^lost+found$') ]] || die "$MNT is not empty; refusing to unpack over existing files"
  fi
  iso_squashfs_mount
  run unsquashfs -f -d "$MNT" "${ISOMNT:-/mnt}/live/filesystem.squashfs"
  run umount "${ISOMNT:-/mnt}"
  run rmdir "${ISOMNT:-/mnt}"
  local ruuid="<root-uuid>"
  (( DRY )) || ruuid=$(blkid -s UUID -o value "$TARGET")
  say "writing $MNT/etc/fstab"
  if (( DRY )); then
    say "+ cat > $MNT/etc/fstab  (root @, /home @home, /.snapshots @snapshots by UUID=$ruuid; /boot/efi UUID=$ESP_FS_UUID vfat nofail)"
    say "+ append canonical shared mounts from $FSTAB_CANONICAL"
  else
    install -d "$MNT/home" "$MNT/.snapshots" "$MNT/boot/efi"
    cat > "$MNT/etc/fstab" <<EOF
# I30LTZ Recovery OS - written by install-recovery-from-debian.sh
UUID=$ruuid  /           btrfs  subvol=@,compress=zstd,noatime           0 0
UUID=$ruuid  /home       btrfs  subvol=@home,compress=zstd,noatime       0 0
UUID=$ruuid  /.snapshots btrfs  subvol=@snapshots,compress=zstd,noatime  0 0
UUID=$ESP_FS_UUID  /boot/efi  vfat  umask=0077,nofail  0 2
EOF
    if [[ -r "$FSTAB_CANONICAL" ]]; then
      echo "" >> "$MNT/etc/fstab"
      cat "$FSTAB_CANONICAL" >> "$MNT/etc/fstab"
      while read -r mp || [[ -n $mp ]]; do
        [[ -n $mp && $mp == /mnt/* ]] && install -d "$MNT$mp"
      done < <(grep '^UUID=' "$FSTAB_CANONICAL" | awk '{print $2}')
    fi
    chmod 644 "$MNT/etc/fstab"
  fi
}

chroot_mounts() {
  run mount --rbind /dev "$MNT/dev"; run mount --make-rslave "$MNT/dev"
  run mount -t proc proc "$MNT/proc"
  run mount -t sysfs sysfs "$MNT/sys"
  run mount --bind /run "$MNT/run"
}

add_firmware_entry() { # runs on the Debian host; appends a boot entry, never reorders the existing ones
  local label="I30LTZ Recovery OS"
  if (( DRY )); then
    say "+ efibootmgr -c -d <disk of $ESP> -p <ESP partition number> -L '$label' -l '\\EFI\\$BOOTLOADER_ID\\shimx64.efi'   (shimx64.efi when grub-install put a shim there, else grubx64.efi)"
    say "+ efibootmgr -o <previous BootOrder>,<new entry>   (keeps the current default first)"
    return 0
  fi
  if [[ ! -d /sys/firmware/efi ]] || ! command -v efibootmgr >/dev/null; then
    say "WARN: no efibootmgr/UEFI here - skipping the firmware entry. The fallback \\EFI\\BOOT\\BOOTX64.EFI still makes the disk bootable from the firmware boot menu."
    return 0
  fi
  local disk part old new stale loader=grubx64.efi
  # Secure Boot: the firmware only starts programs IT can verify. Debian's GRUB is signed with Debian's key (not in the firmware),
  # so the entry must name the Microsoft-signed shim beside it; the shim then loads that GRUB. Without a shim, name the GRUB.
  [[ -f $MNT/boot/efi/EFI/$BOOTLOADER_ID/shimx64.efi ]] && loader=shimx64.efi
  disk=/dev/$(lsblk -ndo PKNAME "$ESP"); part=$(cat "/sys/class/block/$(basename "$ESP")/partition")
  old=$(efibootmgr | sed -n 's/^BootOrder: //p')
  for stale in $(efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\? $label\b.*/\1/p"); do efibootmgr -b "$stale" -B >/dev/null; done
  efibootmgr -c -d "$disk" -p "$part" -L "$label" -l "\\EFI\\$BOOTLOADER_ID\\$loader" >/dev/null \
    || { say "WARN: efibootmgr could not add the entry; the fallback loader still works from the boot menu."; return 0; }
  new=$(efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\? $label\b.*/\1/p" | head -1)
  old=$(echo "$old" | tr ',' '\n' | grep -vx "$new" | paste -sd, -)
  if [[ -n $new ]]; then efibootmgr -o "${old:+$old,}$new" >/dev/null; say "firmware entry Boot$new '$label' added at the END of the boot order ($old stays first)"; fi
}

unmount_install() { # strict for the real filesystems, lazy only for the virtual /sys (cgroup2 can report "busy")
  sync
  if mountpoint -q "$MNT/sys" 2>/dev/null; then run umount -R -l "$MNT/sys" || true; fi
  run umount -R "$MNT"
  if (( ! DRY )) && findmnt -rn -R "$MNT" >/dev/null 2>&1; then
    die "something is still mounted under $MNT: $(findmnt -rn -R -o TARGET "$MNT" | tr '\n' ' ')"
  fi
}

stage_bootloader() {
  need_root
  if (( ! DRY )); then
    mountpoint -q "$MNT" || die "$MNT is not mounted"
    [[ -x $MNT/usr/sbin/grub-install && -x $MNT/usr/sbin/update-initramfs ]] || die "root filesystem is not unpacked (run rootfs first)"
    findmnt -rn -S "$ESP" >/dev/null && die "ESP is mounted elsewhere ($(findmnt -rn -o TARGET -S "$ESP" | head -1)); unmount it first"
  fi
  run install -d "$MNT/boot/efi"
  run mount "$ESP" "$MNT/boot/efi"
  chroot_mounts
  if (( DRY )); then
    say "+ cat > $MNT/etc/default/grub  (GRUB_DISTRIBUTOR='I30LTZ Recovery OS', no os-prober, cmdline 'quiet' - NO boot=live)"
  else
    cat > "$MNT/etc/default/grub" <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="I30LTZ Recovery OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
EOF
  fi
  run chroot "$MNT" update-initramfs -u -k all
  run chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot/efi \
        --bootloader-id="$BOOTLOADER_ID" --no-nvram
  # Standalone fallback path: an existing loader there is kept as a dated backup first.
  local fb="$MNT/boot/efi/EFI/BOOT/BOOTX64.EFI"
  if (( DRY )); then
    say "+ [if $fb exists] cp -a it to BOOTX64.EFI.bak-<date>"
  elif [[ -f $fb ]]; then
    cp -a "$fb" "$fb.bak-$(date +%Y%m%d-%H%M%S)"; say "backed up existing $fb"
  fi
  run chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable --no-nvram
  run chroot "$MNT" update-grub
  add_firmware_entry
  if (( ! DRY )); then
    [[ -f $MNT/boot/efi/EFI/$BOOTLOADER_ID/grubx64.efi ]] || die "grub-install did not produce EFI/$BOOTLOADER_ID/grubx64.efi on the ESP"
    [[ -f $fb ]] || die "grub-install --removable did not produce EFI/BOOT/BOOTX64.EFI on the ESP (not standalone)"
    grep -q 'root=UUID=' "$MNT/boot/grub/grub.cfg" || die "generated grub.cfg has no root=UUID entry"
    grep -q 'boot=live' "$MNT/boot/grub/grub.cfg" && die "generated grub.cfg contains boot=live - that would boot a live session"
    say "bootloader installed: $ESP -> \\EFI\\$BOOTLOADER_ID\\grubx64.efi"
  fi
}

stage_finish() {
  need_root
  (( DRY )) && { say "+ chroot $MNT passwd root"; say "+ umount -R $MNT"; return 0; }
  mountpoint -q "$MNT" || die "$MNT is not mounted"
  say "Set the root password for the installed Recovery OS (the image has no login user - the live"
  say "session only creates one when booted with boot=live):"
  chroot "$MNT" passwd root
  unmount_install
  say "Unmounted. Installed filesystem UUID: $(blkid -s UUID -o value "$TARGET")"
  say "Debian's /etc/fstab line for $DEBIAN_MNT still pins the OLD UUID (490b9e60-...): update it to the new one"
  say "      (it is an x-systemd.automount, nofail line, so a stale UUID is harmless but useless), then: sudo systemctl daemon-reload"
  say "Next: PROVE it is standalone - power off, unplug the Debian drive, pick the Recovery disk from the firmware boot menu"
  say "      (F12 on this Lenovo). Then record the new UUID in /mnt/Lucy/CLAUDE.md. (Adding a Recovery entry to Debian's GRUB"
  say "      menu, grub_themes/09_swarm_debian, is now only a convenience - drop its CachyOS entry while there.)"
}

stage_cleanup() { need_root; if mountpoint -q "$MNT"; then unmount_install; say "unmounted $MNT"; else say "$MNT is not mounted"; fi; }

# ---------------------------------------------------------------- main
LOG=/var/log/i30ltz-recovery-install.log
case $STAGE in
  preflight) preflight; exit $? ;;
  cleanup)   stage_cleanup; exit 0 ;;
esac
preflight || exit 1
if (( ! DRY )) && [[ $EUID -eq 0 ]]; then exec > >(tee -a "$LOG") 2>&1; fi
case $STAGE in
  format)     stage_format ;;
  rootfs)     stage_rootfs ;;
  bootloader) stage_bootloader ;;
  finish)     stage_finish ;;
  all)        stage_format; stage_rootfs; stage_bootloader; stage_finish ;;
esac
say "stage '$STAGE' done."
