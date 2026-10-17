#!/usr/bin/env bash
# Back up the Ubuntu dev home before replacing it with Debian.
# Usage: bash 70-scripts/backup-dev-home.sh /path/to/destination-dir
#
# Writes three things to the destination (NEVER inside a git repo, NEVER on a build partition):
#   dev-home-files.tar.zst    projects, docs, settings (no secrets, no caches)
#   dev-secrets.tar.zst.gpg   ~/.ssh and ~/.gnupg, gpg-symmetric encrypted (asks for a passphrase)
#   dev-home-manifest.txt     package list + sizes for rebuilding the toolchain
# Re-downloadable bulk (caches, ~/.gradle, ~/.rustup, ~/.cargo, Android SDK, snaps) is skipped.
set -euo pipefail

DEST="${1:?usage: $0 /path/to/destination-dir}"
case "$(readlink -f "$DEST")" in
  /mnt/recoverybuild*|/mnt/recoveryos*|/mnt/Lucy*|/mnt/swarmbuild*)
    echo "Refusing: backups must not go on a build partition." >&2; exit 1 ;;
esac
[ -d "$DEST/.git" ] && { echo "Refusing: destination is a git repo." >&2; exit 1; }
mkdir -p "$DEST"
cd "$HOME"

echo "[1/3] files (no secrets, no caches)"
tar --zstd -cf "$DEST/dev-home-files.tar.zst" \
  --exclude='.cache' --exclude='.gradle' --exclude='.rustup' --exclude='.cargo/registry' \
  --exclude='.android' --exclude='snap' --exclude='Android/Sdk' --exclude='ai-dev' \
  --exclude='node_modules' --exclude='target' --exclude='.ssh' --exclude='.gnupg' \
  --exclude='*.env' --exclude='.env*' --exclude='*.pem' --exclude='*client_secret*' \
  --exclude='.config/google-chrome' --exclude='.config/chromium' --exclude='.mozilla' \
  --exclude='.config/Claude' --exclude='.config/Code*' \
  code Documents Desktop Pictures go .claude .config .local/share/applications \
  .bashrc .profile .gitconfig secure-dev-setup.sh 2>/dev/null || true

echo "[2/3] secrets -> encrypted (you will be asked for a passphrase; remember it)"
tar --zstd -cf - .ssh .gnupg 2>/dev/null | gpg --symmetric --cipher-algo AES256 -o "$DEST/dev-secrets.tar.zst.gpg"

echo "[3/3] manifest"
{
  echo "# $(date -Is)  $(. /etc/os-release; echo "$PRETTY_NAME")"
  echo "## apt manual packages"; apt-mark showmanual | sort
  echo "## snaps"; snap list 2>/dev/null || true
  echo "## cargo installs"; ls "$HOME/.cargo/bin" 2>/dev/null || true
  echo "## pip user"; pip list --user 2>/dev/null || true
  echo "## Downloads (review by hand, not copied):"; ls -lh "$HOME/Downloads" 2>/dev/null | head -80
} > "$DEST/dev-home-manifest.txt"

chmod 600 "$DEST"/dev-*
echo "Done:"; ls -lh "$DEST"/dev-*
echo "Verify before wiping Ubuntu:  tar --zstd -tf $DEST/dev-home-files.tar.zst | head"
