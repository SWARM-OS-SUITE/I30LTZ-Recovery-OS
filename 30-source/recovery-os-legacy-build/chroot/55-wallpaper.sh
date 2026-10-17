#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# I30LTZ Recovery OS — chroot/55-wallpaper.sh
# Version: 1.0.1  |  2026-09-26
#
# Bakes HTML wallpaper/splash to PNG and wires them into:
#   • XFCE4 desktop (dr-i30ltz user)
#   • LXQt pcmanfm-qt (if lxqt is installed)
#   • LightDM greeter background
#   • Plymouth boot splash
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
echo "[55-wallpaper] DR. I30LTZ wallpaper setup — $(date)"

LIVE_USER="dr-i30ltz"
LIVE_HOME="/home/${LIVE_USER}"
ASSETS_SRC="/opt/i30ltz/assets"
BG_DIR="/usr/share/backgrounds/i30ltz"
WALLPAPER_HTML="${ASSETS_SRC}/i30ltz-wallpaper.html"
SPLASH_HTML="${ASSETS_SRC}/i30ltz-splash.html"
WALLPAPER_PNG="${BG_DIR}/wallpaper.png"
SPLASH_PNG="${BG_DIR}/splash.png"

mkdir -p "${BG_DIR}" "${ASSETS_SRC}"

# ── 1. Copy HTML assets from build directory ─────────────────────────────────
for f in i30ltz-wallpaper.html i30ltz-splash.html; do
  [[ -f "/build-assets/${f}" ]] && cp "/build-assets/${f}" "${ASSETS_SRC}/${f}"
done

# ── 2. Bake HTML → PNG ───────────────────────────────────────────────────────
bake_png() {
  local src="$1" dst="$2" label="$3"
  echo "[55-wallpaper] Baking ${label} → ${dst}"

  if command -v chromium-browser &>/dev/null; then
    chromium-browser --headless=new --no-sandbox --disable-gpu \
      --disable-dev-shm-usage --window-size=1920,1080 \
      --screenshot="${dst}" --virtual-time-budget=3000 \
      "file://${src}" 2>/dev/null && echo "[55-wallpaper] ✓ ${label} (chromium)" && return 0
  fi

  if command -v chromium &>/dev/null; then
    chromium --headless=new --no-sandbox --disable-gpu \
      --disable-dev-shm-usage --window-size=1920,1080 \
      --screenshot="${dst}" --virtual-time-budget=3000 \
      "file://${src}" 2>/dev/null && echo "[55-wallpaper] ✓ ${label} (chromium)" && return 0
  fi

  if command -v wkhtmltoimage &>/dev/null; then
    wkhtmltoimage --width 1920 --height 1080 --quality 95 \
      "${src}" "${dst}" 2>/dev/null && echo "[55-wallpaper] ✓ ${label} (wkhtmltoimage)" && return 0
  fi

  # ImageMagick colour fallback
  if command -v convert &>/dev/null; then
    convert -size 1920x1080 gradient:'#08080C-#1A1A24' \
      -gravity Center \
      -fill '#BA0C2F' -font DejaVu-Sans-Bold -pointsize 150 -annotate 0 "I30LTZ" \
      -fill '#F5A623' -pointsize 60 -annotate +0+200 "RECOVERY OS" \
      "${dst}" 2>/dev/null && echo "[55-wallpaper] ✓ ${label} (imagemagick fallback)" && return 0
  fi

  echo "[55-wallpaper] ✗ Could not render ${label} — no renderer available" && return 1
}

[[ -f "${WALLPAPER_HTML}" ]] && bake_png "${WALLPAPER_HTML}" "${WALLPAPER_PNG}" "wallpaper"
[[ -f "${SPLASH_HTML}"   ]] && bake_png "${SPLASH_HTML}"   "${SPLASH_PNG}"   "splash"

# ── 3. XFCE4 desktop wallpaper (updates existing config written by 10-desktop.sh)
configure_xfce4() {
  echo "[55-wallpaper] Patching XFCE4 desktop config for ${LIVE_USER}"
  XFCE_XML="${LIVE_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
  mkdir -p "$(dirname "${XFCE_XML}")"

  # Overwrite with version that includes the wallpaper path
  cat > "${XFCE_XML}" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!-- I30LTZ Recovery OS — XFCE4 desktop config — 2026-09-26 -->
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style"    type="int"    value="0"/>
          <property name="image-style"    type="int"    value="5"/>
          <property name="last-image"     type="string" value="${WALLPAPER_PNG}"/>
          <property name="rgba1" type="array">
            <value type="double" value="0.031373"/>
            <value type="double" value="0.031373"/>
            <value type="double" value="0.047059"/>
            <value type="double" value="1.000000"/>
          </property>
        </property>
      </property>
    </property>
  </property>
</channel>
XML

  chown "${LIVE_USER}:${LIVE_USER}" "${XFCE_XML}"
  echo "[55-wallpaper] ✓ XFCE4 wallpaper path set"
}

# ── 4. LXQt wallpaper (if installed) ────────────────────────────────────────
configure_lxqt() {
  if ! dpkg -l lxqt-core &>/dev/null; then
    echo "[55-wallpaper] LXQt not installed — skipping"
    return 0
  fi
  echo "[55-wallpaper] Configuring LXQt wallpaper for ${LIVE_USER}"
  LXQT_CONF="${LIVE_HOME}/.config/pcmanfm-qt/lxqt"
  mkdir -p "${LXQT_CONF}"
  cat > "${LXQT_CONF}/settings.conf" <<INI
[Desktop]
BgMode=fill
WallpaperFile=${WALLPAPER_PNG}
WallpaperMode=stretch
WallpaperRandomize=false
INI
  chown -R "${LIVE_USER}:${LIVE_USER}" "${LIVE_HOME}/.config/pcmanfm-qt"
  echo "[55-wallpaper] ✓ LXQt wallpaper set"
}

# ── 5. LightDM greeter background ───────────────────────────────────────────
configure_lightdm() {
  echo "[55-wallpaper] Setting LightDM greeter background"
  # Patch the existing greeter config written by 10-desktop.sh
  GREETER="/etc/lightdm/lightdm-gtk-greeter.conf"
  if [[ -f "${GREETER}" ]]; then
    if grep -q "^background=" "${GREETER}"; then
      sed -i "s|^background=.*|background=${WALLPAPER_PNG}|" "${GREETER}"
    else
      echo "background=${WALLPAPER_PNG}" >> "${GREETER}"
    fi
  fi
  echo "[55-wallpaper] ✓ LightDM greeter background updated"
}

# ── 6. Plymouth boot splash ──────────────────────────────────────────────────
configure_plymouth() {
  echo "[55-wallpaper] Configuring Plymouth theme"
  PLYM="/usr/share/plymouth/themes/i30ltz"
  mkdir -p "${PLYM}"

  [[ -f "${SPLASH_PNG}" ]] && cp "${SPLASH_PNG}" "${PLYM}/background.png"

  cat > "${PLYM}/i30ltz.plymouth" <<PLY
[Plymouth Theme]
Name=I30LTZ Recovery
Description=I30LTZ Recovery OS Boot Splash — 2026-09-26
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/i30ltz
ScriptFile=/usr/share/plymouth/themes/i30ltz/i30ltz.script
PLY

  cat > "${PLYM}/i30ltz.script" <<'PLYSCRIPT'
# I30LTZ Plymouth script — Version 1.0.0 | 2026-09-26
screen_width  = Window.GetWidth();
screen_height = Window.GetHeight();

bg = Image("background.png");
bg_s = bg.Scale(screen_width, screen_height);
Sprite(bg_s).SetZ(-100);

# Red → yellow progress strip at bottom
bar_h = 6;
bar_y = screen_height - bar_h;
img   = Image.NewBuffer(screen_width, bar_h);
for (x = 0; x < screen_width; x++) {
  t = x / screen_width;
  img.DrawPixel(x, 0, (186 + t*59)/255, (12 + t*154)/255, 47/255, 1.0);
}
bar = Sprite(img);
bar.SetPosition(0, bar_y, 1);
bar.SetOpacity(0);

fun BootProgress.SetProgressCallback (duration, progress) {
  bar.SetOpacity(1);
  bar.SetClip(0, 0, Math.Int(screen_width * progress), bar_h);
}
PLYSCRIPT

  if command -v update-alternatives &>/dev/null; then
    update-alternatives --install \
      /usr/share/plymouth/themes/default.plymouth \
      default.plymouth "${PLYM}/i30ltz.plymouth" 100 2>/dev/null || true
  fi
  command -v update-initramfs &>/dev/null && update-initramfs -u 2>/dev/null || true
  echo "[55-wallpaper] ✓ Plymouth theme installed"
}

configure_xfce4
configure_lxqt
configure_lightdm
configure_plymouth

echo "[55-wallpaper] ── Complete ────────────────────────────────────────────"
echo "[55-wallpaper]   Wallpaper : ${WALLPAPER_PNG}"
echo "[55-wallpaper]   Splash    : ${SPLASH_PNG}"
