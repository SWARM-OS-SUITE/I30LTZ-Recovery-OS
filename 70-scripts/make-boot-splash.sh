#!/usr/bin/env bash
# Generate the live-build boot-menu splash from the Dr. Boltz art (syslinux BIOS + GRUB EFI), 2026-10-12.
# Usage: make-boot-splash.sh <live-build config dir>   (build.sh passes 40-iso-profile/config)
# Writes <cfg>/bootloaders/splash.svg  (live-build renders it to splash.png: 640x480 syslinux, 800x600 grub)
#    and <cfg>/bootloaders/grub-pc/live-theme/theme.txt (stock theme with the "Live Boot Menu with GRUB" title removed).
# live-build 20250505 OVERLAYS config/bootloaders/<name>/ on its defaults, so only these two files are replaced.
# The boot menu covers the lower half of the screen: the art sits in the top half and fades to black.
set -euo pipefail
CFG="${1:?config dir}"
SRC="/mnt/recoverybuild/30-source/recovery-os-images/dr-boltz.jpg"
THEME_SRC="/usr/share/live/build/bootloaders/grub-pc/live-theme/theme.txt"
[ -f "$SRC" ] || { echo "[SPLASH] $SRC missing - keeping live-build's default splash" >&2; exit 0; }
mkdir -p "$CFG/bootloaders/grub-pc/live-theme"
B64=$(base64 -w0 "$SRC")
cat > "$CFG/bootloaders/splash.svg" <<SVG
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="800" height="600" viewBox="0 0 800 600">
  <defs>
    <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity="1"/>
    </linearGradient>
  </defs>
  <rect width="800" height="600" fill="#000"/>
  <image x="0" y="-30" width="800" height="447" preserveAspectRatio="xMidYMid slice" xlink:href="data:image/jpeg;base64,${B64}"/>
  <rect x="0" y="270" width="800" height="130" fill="url(#fade)"/>
  <rect x="0" y="399" width="800" height="201" fill="#000"/>
</svg>
SVG
if [ -f "$THEME_SRC" ]; then
  sed 's|^title-text:.*|title-text: ""|' "$THEME_SRC" > "$CFG/bootloaders/grub-pc/live-theme/theme.txt"
fi
echo "[SPLASH] wrote $CFG/bootloaders/splash.svg ($(du -h "$CFG/bootloaders/splash.svg" | cut -f1))"
