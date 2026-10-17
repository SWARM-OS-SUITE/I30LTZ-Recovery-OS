#!/usr/bin/env bash
# [FIX-C1] I30LTZ_BAKE_MODEL set by 01-bake-model.sh 2026-10-06
export I30LTZ_BAKE_MODEL=1  # Bake qwen2.5:7b into ISO at build time (offline-first)
# I30LTZ Recovery OS — Main Build Script
# Version: 0.3.0-alpha | Date: 2026-10-05
# Base OS: Debian 13 trixie (live-build, Debian mode)
# Run: sudo bash /mnt/recoverybuild/70-scripts/build.sh
# -------------------------------------------------------

set -e

ROOT="/mnt/recoverybuild"
ISO_PROFILE="$ROOT/40-iso-profile"
# ISO output (user policy 2026-10-07): newest 5 on Ventoy, newest 1 on the PC.
VENTOY="/mnt/ventoy"
VENTOY_UUID="5ABB-83DF"
RELEASES="$VENTOY/ISO/recovery-os"
LOCAL_RELEASES="$ROOT/10-releases"
STAMP=$(date +%Y%m%d-%H%M)
# lb names the ISO after the distribution (e.g. live-image-amd64.hybrid.iso)
# We rename it to our scheme after build.
ISO_NAME="i30ltz-recovery-0.3.0-alpha-${STAMP}-amd64.iso"
LOG="$ROOT/00-CURRENT/build-${STAMP}.log"

# ── Preflight ─────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  I30LTZ Recovery OS — Build v0.3.0-alpha         ║"
echo "║  $(date -u +%Y-%m-%dT%H:%M:%SZ)                  ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Ventoy must be the right mounted device; missing media aborts (never fall back locally)
if ! mountpoint -q "$VENTOY" || [ "$(findmnt -no UUID "$VENTOY" 2>/dev/null)" != "$VENTOY_UUID" ]; then
  echo "[BUILD] ❌ Ventoy ($VENTOY_UUID) is not mounted at $VENTOY - aborting; no local fallback." >&2
  exit 1
fi

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "[BUILD] ERROR: Run with sudo" >&2
  exit 1
fi

# ── Host diagnostics + Rust-coreutils guard ───────────────
echo "[BUILD] Host: $(. /etc/os-release; echo "$PRETTY_NAME") | kernel $(uname -r)"
CHROOT_VER="$(chroot --version 2>&1 | head -1)"
echo "[BUILD] chroot: $CHROOT_VER"
echo "[BUILD] debootstrap: $(dpkg-query -W -f='${Version}' debootstrap 2>/dev/null || echo not-installed)"
echo "[BUILD] build mount: $(findmnt -n -o OPTIONS --target "$ROOT" 2>/dev/null)"
if echo "$CHROOT_VER" | grep -qi "uutils"; then
  echo ""
  echo "[BUILD] ❌ Host chroot is Rust uutils-coreutils. It fails inside debootstrap/live-build"
  echo "[BUILD]    ('failed to run command /usr/bin/env ... os error 2')."
  echo "[BUILD]    Fix (reversible):"
  echo "[BUILD]      sudo apt install coreutils-from-gnu     # build"
  echo "[BUILD]      sudo apt install coreutils-from-uutils  # restore afterwards"
  echo "[BUILD]    Then re-run this script."
  exit 1
fi
case "$(findmnt -n -o OPTIONS --target "$ROOT" 2>/dev/null)" in
  *noexec*|*nodev*) echo "[BUILD] ❌ $ROOT is mounted noexec/nodev - chroot builds need exec+dev."
     echo "[BUILD]    sudo mount -o remount,exec,dev $ROOT"; exit 1 ;;
esac
# Stale bootstrap cache from a failed run poisons retries
if [ "${I30LTZ_FRESH:-0}" = "1" ]; then
  echo "[BUILD] I30LTZ_FRESH=1 - wiping lb cache/chroot"
  rm -rf "$ISO_PROFILE/cache" "$ISO_PROFILE/chroot" "$ISO_PROFILE/.build"
fi

# Self-heal: a stale ".build" stamp + empty chroot makes lb print
# "skipping bootstrap, already done" and then fail on an empty chroot.
if [ -d "$ISO_PROFILE/.build" ] && [ ! -x "$ISO_PROFILE/chroot/usr/bin/env" ]; then
  echo "[BUILD] Stale lb state (stamp present, chroot empty) - wiping .build/cache/chroot"
  ( cd "$ISO_PROFILE" && lb clean --purge >/dev/null 2>&1 || true )
  rm -rf "$ISO_PROFILE/.build" "$ISO_PROFILE/cache" "$ISO_PROFILE/chroot"
fi

# Check live-build is installed
if ! command -v lb &>/dev/null; then
  echo "[BUILD] Installing live-build..."
  apt-get update -qq
  apt-get install -y live-build
fi

# Recovery app (Rust) lives in this repo: 30-source/i30ltz-recovery (single source).
# Build it as a normal user first:  cd 30-source/i30ltz-recovery && CARGO_HOME=$ROOT/25-toolchain/cargo-home cargo build --release --locked
APP_SRC="$ROOT/30-source/i30ltz-recovery"
BINARY="$APP_SRC/target/release/i30ltz-recovery"
if [ -f "$BINARY" ]; then
  install -m 755 "$BINARY" "$ISO_PROFILE/config/includes.chroot/usr/local/bin/i30ltz-recovery"
  echo "[BUILD] Staged recovery app from $BINARY"
else
  echo "[BUILD] WARNING: Rust binary not found at $BINARY"
  echo "[BUILD]   Build it first: cd $APP_SRC && CARGO_HOME=$ROOT/25-toolchain/cargo-home cargo build --release --locked"
  echo "[BUILD]   Continuing anyway — existing/stub launcher will be used."
fi

# Recovery OS art (copied from SWARM's websitebackgrounds, see 30-source/recovery-os-images/README.md):
# images go to /opt/i30ltz/images (the kiosk loads dr-boltz.jpg from there), and the boot-menu splash is generated.
IMG_SRC="$ROOT/30-source/recovery-os-images"
if [ -d "$IMG_SRC" ]; then
  rm -rf "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/images"
  mkdir -p "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/images"
  cp -a "$IMG_SRC"/*.jpg "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/images/"
  # fonts used by the Recovery console (Lato + Hack, licences included): /opt/i30ltz/fonts
  rm -rf "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/fonts"
  mkdir -p "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/fonts"
  cp -a "$IMG_SRC"/fonts/. "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/fonts/"
  echo "[BUILD] Staged Recovery OS images from $IMG_SRC"
  bash "$ROOT/70-scripts/make-boot-splash.sh" "$ISO_PROFILE/config"
else
  echo "[BUILD] WARNING: $IMG_SRC missing - no themed images/boot splash (kiosk falls back to its plain look)"
fi

# I30LTZ IDE (Flutter, RC-14) lives in 30-source/i30ltz-ide. Build it as a normal user first:  bash 70-scripts/build-ide.sh
# Never build Flutter as root. The bundle is copied to /opt/i30ltz/ide in the ISO (launcher: usr/local/bin/i30ltz-ide).
IDE_BUNDLE="$ROOT/30-source/i30ltz-ide/build/linux/x64/release/bundle"
if [ -x "$IDE_BUNDLE/i30ltz_ide" ]; then
  rm -rf "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/ide"
  mkdir -p "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/ide"
  cp -a "$IDE_BUNDLE/." "$ISO_PROFILE/config/includes.chroot/opt/i30ltz/ide/"
  echo "[BUILD] Staged I30LTZ IDE from $IDE_BUNDLE"
else
  echo "[BUILD] WARNING: I30LTZ IDE bundle not found at $IDE_BUNDLE"
  echo "[BUILD]   Build it first (normal user): bash $ROOT/70-scripts/build-ide.sh"
  echo "[BUILD]   Continuing anyway: the ISO will have no IDE (launcher i30ltz-ide will fail)."
fi

mkdir -p "$RELEASES"
mkdir -p "$ROOT/00-CURRENT"

# ── Run live-build ────────────────────────────────────────
# Single-source sync: brain code lives ONLY in 30-source; copied in at build time
IC="$ISO_PROFILE/config/includes.chroot"
mkdir -p "$IC/opt/i30ltz/brain"
cp "$ROOT/30-source/mad-dr-boltz/brain/boltz_server.py" \
   "$ROOT/30-source/mad-dr-boltz/brain/requirements.txt" "$IC/opt/i30ltz/brain/"
echo "[BUILD] Synced brain -> includes.chroot (single source)"

echo "[BUILD] Entering ISO profile: $ISO_PROFILE"
cd "$ISO_PROFILE"

# Make hook scripts executable
find config/hooks -name "*.hook.chroot" -exec chmod +x {} \;
chmod +x auto/config 2>/dev/null || true

echo "[BUILD] Running: lb config ..."
bash auto/config 2>&1 | tee -a "$LOG"

echo "[BUILD] Running: lb build ... (this takes 20-45 min)"
lb build 2>&1 | tee -a "$LOG"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "[BUILD] ❌ lb build FAILED - first real error is above; full log: $LOG"
  grep -n -m5 -E '^E:|error|Error|failed' "$LOG" | head -5
  exit 1
fi

# ── Move ISO to releases ──────────────────────────────────
# lb outputs: live-image-amd64.hybrid.iso
BUILT_ISO=$(find "$ISO_PROFILE" -maxdepth 1 -name "*.iso" -o -name "*.img" 2>/dev/null | head -1)
if [ -n "$BUILT_ISO" ]; then
  mv "$BUILT_ISO" "$RELEASES/$ISO_NAME"
  SHA=$(sha256sum "$RELEASES/$ISO_NAME" | awk '{print $1}')
  echo "$SHA  $ISO_NAME" > "$RELEASES/$ISO_NAME.sha256"

  # Retention (user policy 2026-10-06): keep the newest five Recovery OS ISOs.
  # Only this OS's own i30ltz-recovery-*.iso files are counted or removed.
  find "$RELEASES" -maxdepth 1 -name 'i30ltz-recovery-*.iso' -printf '%T@ %p\n' \
    | sort -rn | tail -n +6 | cut -d' ' -f2- \
    | while IFS= read -r old; do
        echo "[BUILD] retention: removing $(basename "$old")"
        rm -f -- "$old" "$old.sha256"
      done

  # Local copy (user policy 2026-10-07): exactly one ISO, the newest, on the PC.
  mkdir -p "$LOCAL_RELEASES"
  find "$LOCAL_RELEASES" -maxdepth 1 -name 'i30ltz-recovery-*.iso*' -delete
  cp -- "$RELEASES/$ISO_NAME" "$RELEASES/$ISO_NAME.sha256" "$LOCAL_RELEASES/"

  echo ""
  echo "[BUILD] ✅ ISO built:"
  echo "[BUILD]    $RELEASES/$ISO_NAME"
  echo "[BUILD]    local copy: $LOCAL_RELEASES/$ISO_NAME"
  echo "[BUILD]    SHA256: $SHA"
  echo ""
  echo "[BUILD] Test in QEMU:"
  echo "   bash $ROOT/70-scripts/test-iso-vm.sh recovery --iso $LOCAL_RELEASES/$ISO_NAME"
  echo ""
  echo "[BUILD] Stage AI model, then write USB with persistence (>=16 GB stick):"
  echo "   bash $ROOT/50-backends/stage-model.sh"
  echo "   sudo bash $ROOT/70-scripts/make-persistent-usb.sh /dev/sdX $RELEASES/$ISO_NAME"
else
  echo "[BUILD] ❌ ISO not found after build — check $LOG"
  exit 1
fi

# ── Update build state ────────────────────────────────────
cat >> "$ROOT/00-CURRENT/BUILD_STATE.md" << BSTATE

## Build Run ${STAMP}
- ISO: $ISO_NAME
- SHA256: $SHA
- Log: $LOG
BSTATE

echo "[BUILD] Build log: $LOG"
