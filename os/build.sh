#!/usr/bin/env bash
# =============================================================================
# I30LTZ Recovery OS — build the OS image
# v0.1.0 · 2026-10-01
#
#   cd os && sudo bash build.sh            # build  → out/v<version>_<date>/
#   sudo bash build.sh --clean             # wipe caches first (slow, from scratch)
#
# Uses a pinned mkosi v26 (Ubuntu 24.04's packaged mkosi 20.2 can't build
# noble images). Build tools run in a sandboxed Ubuntu tree, so this machine's
# own bootloader is never touched. Output: a disk image plus split ESP/root
# partition images for install-to-drive.sh, all with SHA256SUMS.
# =============================================================================
set -euo pipefail
OS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MKOSI_TAG="v26"
MKOSI_COMMIT="84af20892b61c8e177e391f997ded8b4cb5514f2"
MKOSI_DIR="/var/cache/i30ltz/mkosi-${MKOSI_TAG}"
VERSION="$(cat "$OS_DIR/mkosi.version")"
DATE="$(date -u +%F)"
DEST="$OS_DIR/out/v${VERSION}_${DATE}"

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
yel()   { printf '\033[1;33m%s\033[0m\n' "$*"; }
[[ $EUID -eq 0 ]] || { red "run as root:  sudo bash $0"; exit 1; }

red   "  I30LTZ RECOVERY OS · image build"
yel   "  version ${VERSION} · ${DATE} · mkosi ${MKOSI_TAG}"
echo

# ── host needs: python3, git, bubblewrap (everything else is sandboxed) ────
missing=()
for c in python3 git bwrap; do command -v "$c" >/dev/null || missing+=("$c"); done
if ((${#missing[@]})); then
  yel "installing build prerequisites: ${missing[*]}"
  apt-get install -y python3 git bubblewrap
fi

# ── pinned mkosi ────────────────────────────────────────────────────────────
if [[ ! -x "$MKOSI_DIR/bin/mkosi" ]]; then
  yel "fetching mkosi ${MKOSI_TAG}…"
  mkdir -p "$(dirname "$MKOSI_DIR")"
  git clone -q --depth 1 -b "$MKOSI_TAG" https://github.com/systemd/mkosi "$MKOSI_DIR"
fi
got="$(git -C "$MKOSI_DIR" rev-parse HEAD)"
[[ "$got" == "$MKOSI_COMMIT" ]] || { red "mkosi checkout is $got, expected $MKOSI_COMMIT — delete $MKOSI_DIR and retry"; exit 1; }

# ── space check: tools tree + image + cache need ~25G ──────────────────────
free_gb=$(df -BG --output=avail "$OS_DIR" | tail -1 | tr -dc '0-9')
(( free_gb >= 25 )) || { red "need 25G free next to $OS_DIR (have ${free_gb}G)"; exit 1; }

cd "$OS_DIR"
[[ "${1:-}" == --clean ]] && rm -rf mkosi.cache mkosi.tools out/*.raw out/*.efi
mkdir -p mkosi.cache
"$MKOSI_DIR/bin/mkosi" --image-version="$VERSION" -f build

# ── organize output: out/v<version>_<date>/ with checksums ─────────────────
mkdir -p "$DEST"
shopt -s nullglob
for f in out/i30ltz-recovery-os_"$VERSION"*; do
  [[ -L "$f" ]] && continue
  mv -f "$f" "$DEST/"
done
( cd "$DEST" && sha256sum ./*.raw > SHA256SUMS )
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OS_DIR/out"
echo
red "  ✅ built I30LTZ Recovery OS ${VERSION} (${DATE})"
ls -lh "$DEST"
echo
yel "  test it in a VM:   sudo bash $OS_DIR/test-vm.sh $DEST"
yel "  install to boltz:  sudo bash $OS_DIR/install-to-drive.sh $DEST /dev/sdX"
