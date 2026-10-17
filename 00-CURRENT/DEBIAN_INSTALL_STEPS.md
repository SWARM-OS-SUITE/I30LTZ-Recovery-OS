# Debian install: steps and commands (saved 2026-10-06)
Find this again: `/mnt/recoverybuild/00-CURRENT/DEBIAN_INSTALL_STEPS.md` (also a copy on the Ventoy stick: `DEBIAN_INSTALL_STEPS.txt`).
No secrets in this file. Related: `MASTER_BUILD_LIST.md`, `MOUNTS.md`, `AI_INSTRUCTIONS.md`.

## BEFORE wiping Ubuntu (run in Ubuntu; the leading ! is only for the Claude prompt, drop it in a normal terminal)
1. Back up (asks for a passphrase for the encrypted .ssh/.gnupg file; remember it):
   bash /mnt/recoverybuild/70-scripts/backup-dev-home.sh /mnt/downloads/ubuntu-backup-2026-10-06
2. Verify:
   tar --zstd -tf /mnt/downloads/ubuntu-backup-2026-10-06/dev-home-files.tar.zst | head
3. Copy the 3 backup files to a SECOND place (e.g. /mnt/storage). /mnt/downloads is on the same disk you are about to wipe.
4. Check Docker data (not in the backup):  docker volume ls
5. Wi-Fi passwords are not backed up: have them ready.

## Install (boot the Ventoy stick -> debian-13.7.0-amd64-DVD-1.iso)
- Graphical install; say YES to non-free firmware.
- Partitioning = MANUAL. Touch ONLY these two partitions on the 1.8 TB Micron USB disk:
    1 GB vfat (1st)        -> use as EFI System Partition, DO NOT FORMAT
    300 GB btrfs (2nd, Ubuntu /) -> format (ext4 simplest; btrfs for snapshots), mount as /
  Every other partition on every disk -> "Do not use". Go by size/filesystem, not sdX letters. If unsure: stop.
- Desktop: LXQt or XFCE + standard system utilities. Leave SSH server UNCHECKED. GRUB to the EFI partition.

## First boot of Debian
1. Add the lines from /mnt/recoverybuild/70-scripts/fstab.canonical to /etc/fstab (use sudoedit), then:
   sudo systemctl daemon-reload && sudo mount -a
2. bash /mnt/recoverybuild/70-scripts/check-mounts.sh        # want: ALL OK
3. Restore files:   tar --zstd -xf /mnt/downloads/ubuntu-backup-2026-10-06/dev-home-files.tar.zst -C ~
   Restore secrets: gpg -d /mnt/downloads/ubuntu-backup-2026-10-06/dev-secrets.tar.zst.gpg | tar --zstd -xf - -C ~
   Then: chmod 700 ~/.ssh ~/.gnupg
4. Basics:  sudo apt install -y git curl build-essential nodejs npm
   Claude Code: npm config set prefix ~/.local && npm install -g @anthropic-ai/claude-code   (add ~/.local/bin to PATH)
5. cd /mnt/recoverybuild && claude     # tell it: "read 00-CURRENT/MASTER_BUILD_LIST.md, then do INF-06 (Debian dev toolchain)"
6. Install the mount-check timer again on Debian:
   mkdir -p ~/.config/systemd/user && cp /mnt/recoverybuild/70-scripts/mount-check.{service,timer} ~/.config/systemd/user/
   systemctl --user daemon-reload && systemctl --user enable --now mount-check.timer
