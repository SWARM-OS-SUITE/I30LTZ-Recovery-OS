#!/usr/bin/env bash
# ============================================================
#  I30LTZ RECOVERY OS — Master Build Script
#  Version: 1.0.0  |  Date: 2026-09-25
#  AI: DR. I30LTZ "MAD IT"
#  Base: Ubuntu 24.04 LTS (Noble) + XFCE4
# ============================================================
set -euo pipefail

# ── Config ──────────────────────────────────────────────────
OS_NAME="I30LTZ Recovery OS"
OS_VERSION="1.0.0"
OS_CODENAME="NIGHTFALL"
BUILD_DATE="$(date +%Y-%m-%d)"
BASE_URL="http://archive.ubuntu.com/ubuntu"
UBUNTU_REL="noble"        # 24.04 LTS
ARCH="amd64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build"
CHROOT_DIR="${BUILD_DIR}/chroot"
ISO_DIR="${BUILD_DIR}/iso"
OUT_DIR="${SCRIPT_DIR}/releases"
ISO_NAME="i30ltz-recovery-os_${OS_VERSION}_${BUILD_DATE}_${ARCH}.iso"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; MAG='\033[0;35m'; CYN='\033[0;36m'
WHT='\033[1;37m'; RST='\033[0m'
BOLD='\033[1m'

banner() {
  echo -e "${RED}${BOLD}"
  cat << 'EOF'
 ██╗██████╗  ██████╗ ██╗  ████████╗███████╗
 ██║╚════██╗██╔═══██╗██║  ╚══██╔══╝╚════██║
 ██║ █████╔╝██║   ██║██║     ██║       ██╔╝
 ██║ ╚═══██╗██║   ██║██║     ██║      ██╔╝
 ██║██████╔╝╚██████╔╝███████╗██║      ██║
 ╚═╝╚═════╝  ╚═════╝ ╚══════╝╚═╝      ╚═╝
  RECOVERY OS — DR. I30LTZ "MAD IT" BUILD SYSTEM
EOF
  echo -e "${RST}"
  echo -e "${WHT}OS:${RST}       ${OS_NAME} v${OS_VERSION} (${OS_CODENAME})"
  echo -e "${WHT}Base:${RST}     Ubuntu ${UBUNTU_REL} 24.04 LTS"
  echo -e "${WHT}Date:${RST}     ${BUILD_DATE}"
  echo -e "${WHT}Target:${RST}   ${ISO_DIR}/${ISO_NAME}"
  echo ""
}

log()  { echo -e "${BLU}[BUILD]${RST} $*"; }
ok()   { echo -e "${GRN}[ OK  ]${RST} $*"; }
warn() { echo -e "${YLW}[ WARN]${RST} $*"; }
die()  { echo -e "${RED}[FATAL]${RST} $*"; exit 1; }

check_deps() {
  log "Checking build dependencies..."
  local deps=(debootstrap squashfs-tools genisoimage xorriso mtools syslinux-utils)
  local missing=()
  for d in "${deps[@]}"; do
    command -v "$d" &>/dev/null || missing+=("$d")
  done
  [[ ${#missing[@]} -gt 0 ]] && die "Missing: ${missing[*]} — run: sudo apt install ${missing[*]}"
  ok "All build deps present"
}

must_root() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo $0 $*"
}

# ── Stage 1: debootstrap ─────────────────────────────────────
stage_debootstrap() {
  log "Stage 1 — debootstrap Ubuntu ${UBUNTU_REL}..."
  if [[ -f "${CHROOT_DIR}/etc/os-release" ]]; then
    warn "Chroot exists, skipping debootstrap (rm ${CHROOT_DIR} to force)"
    return
  fi
  mkdir -p "${CHROOT_DIR}"
  debootstrap \
    --arch="${ARCH}" \
    --include=sudo,curl,wget,gnupg2,ca-certificates,locales,systemd \
    "${UBUNTU_REL}" \
    "${CHROOT_DIR}" \
    "${BASE_URL}"
  ok "Stage 1 complete — chroot at ${CHROOT_DIR}"
}

# ── Stage 2: run chroot scripts ───────────────────────────────
stage_chroot() {
  log "Stage 2 — running chroot customization scripts..."

  # Mount pseudo-filesystems
  mount --bind /dev     "${CHROOT_DIR}/dev"
  mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
  mount --bind /proc    "${CHROOT_DIR}/proc"
  mount --bind /sys     "${CHROOT_DIR}/sys"
  mount --bind /run     "${CHROOT_DIR}/run"

  # Inject resolv.conf
  cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

  # Copy all chroot scripts + config into chroot
  cp -r "${SCRIPT_DIR}/chroot/"* "${CHROOT_DIR}/tmp/chroot-scripts/"
  cp -r "${SCRIPT_DIR}/config/"  "${CHROOT_DIR}/tmp/i30ltz-config/"
  cp -r "${SCRIPT_DIR}/sse-server/" "${CHROOT_DIR}/tmp/sse-server/"

  # Execute each numbered script in order
  for script in "${SCRIPT_DIR}/chroot/"[0-9][0-9]-*.sh; do
    name="$(basename "$script")"
    log "  → Running ${name}"
    chroot "${CHROOT_DIR}" /bin/bash "/tmp/chroot-scripts/${name}" \
      || die "Script failed: ${name}"
    ok "  ✓ ${name} done"
  done

  # Cleanup mounts
  umount -lf "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
  umount -lf "${CHROOT_DIR}/dev"     2>/dev/null || true
  umount -lf "${CHROOT_DIR}/proc"    2>/dev/null || true
  umount -lf "${CHROOT_DIR}/sys"     2>/dev/null || true
  umount -lf "${CHROOT_DIR}/run"     2>/dev/null || true

  ok "Stage 2 complete"
}

# ── Stage 3: squashfs ─────────────────────────────────────────
stage_squashfs() {
  log "Stage 3 — building squashfs filesystem..."
  mkdir -p "${ISO_DIR}/live"
  # Remove apt cache to shrink image
  rm -rf "${CHROOT_DIR}/var/cache/apt/archives/"*.deb 2>/dev/null || true
  mksquashfs \
    "${CHROOT_DIR}" \
    "${ISO_DIR}/live/filesystem.squashfs" \
    -comp xz -Xbcj x86 -b 1048576 \
    -e "${CHROOT_DIR}/proc" \
    -e "${CHROOT_DIR}/sys" \
    -e "${CHROOT_DIR}/dev" \
    -e "${CHROOT_DIR}/run" \
    -noappend
  ok "Stage 3 complete — $(du -sh "${ISO_DIR}/live/filesystem.squashfs" | cut -f1) squashfs"
}

# ── Stage 4: kernel + initrd ──────────────────────────────────
stage_kernel() {
  log "Stage 4 — copying kernel + initrd..."
  mkdir -p "${ISO_DIR}/casper"
  cp "${CHROOT_DIR}/boot/vmlinuz-"* "${ISO_DIR}/casper/vmlinuz"
  cp "${CHROOT_DIR}/boot/initrd.img-"* "${ISO_DIR}/casper/initrd"
  ok "Stage 4 complete"
}

# ── Stage 5: GRUB boot image ───────────────────────────────────
stage_grub() {
  log "Stage 5 — building GRUB EFI + BIOS boot..."

  cp "${SCRIPT_DIR}/config/grub/grub.cfg" "${ISO_DIR}/boot/grub/grub.cfg"

  # Write grub.cfg version info
  sed -i "s/%%VERSION%%/${OS_VERSION}/g"    "${ISO_DIR}/boot/grub/grub.cfg"
  sed -i "s/%%BUILD_DATE%%/${BUILD_DATE}/g" "${ISO_DIR}/boot/grub/grub.cfg"

  # filesystem manifest
  chroot "${CHROOT_DIR}" dpkg-query -W \
    --showformat='${Package} ${Version}\n' \
    > "${ISO_DIR}/live/filesystem.manifest"

  ok "Stage 5 complete"
}

# ── Stage 6: ISO assembly ────────────────────────────────────
stage_iso() {
  log "Stage 6 — assembling ISO..."
  mkdir -p "${OUT_DIR}"

  xorriso -as mkisofs \
    -iso-level 3 \
    -o "${OUT_DIR}/${ISO_NAME}" \
    -full-iso9660-filenames \
    -volid "I30LTZ_RECOVERY_OS" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-boot boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --efi-boot boot/grub/efi.img \
    -efi-boot-part --efi-boot-image \
    "${ISO_DIR}" 2>&1 | tail -5

  local sz; sz="$(du -sh "${OUT_DIR}/${ISO_NAME}" | cut -f1)"
  ok "Stage 6 complete — ${OUT_DIR}/${ISO_NAME} (${sz})"
  echo ""
  echo -e "${RED}${BOLD}╔══════════════════════════════════════════════╗"
  echo -e "║  I30LTZ RECOVERY OS BUILD COMPLETE           ║"
  printf  "║  %-44s║\n" "Version: ${OS_VERSION}  |  ${BUILD_DATE}"
  printf  "║  %-44s║\n" "Size: ${sz}"
  echo -e "╚══════════════════════════════════════════════╝${RST}"
}

# ── Entrypoint ───────────────────────────────────────────────
main() {
  banner
  must_root
  check_deps

  local stage="${1:-all}"
  case "$stage" in
    1|debootstrap) stage_debootstrap ;;
    2|chroot)      stage_chroot ;;
    3|squashfs)    stage_squashfs ;;
    4|kernel)      stage_kernel ;;
    5|grub)        stage_grub ;;
    6|iso)         stage_iso ;;
    all)
      stage_debootstrap
      stage_chroot
      stage_squashfs
      stage_kernel
      stage_grub
      stage_iso
      ;;
    *)
      echo "Usage: $0 [1-6|all]"
      echo "  1 debootstrap   — base Ubuntu chroot"
      echo "  2 chroot        — install packages + config"
      echo "  3 squashfs      — compress filesystem"
      echo "  4 kernel        — copy vmlinuz + initrd"
      echo "  5 grub          — build GRUB boot"
      echo "  6 iso           — assemble final ISO"
      echo "  all             — full build"
      ;;
  esac
}

main "$@"
