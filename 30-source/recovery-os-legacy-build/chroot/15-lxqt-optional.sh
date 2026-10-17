#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# I30LTZ Recovery OS — chroot/15-lxqt-optional.sh
# Version: 1.0.0  |  2026-09-26
#
# OPTIONAL: Run AFTER 10-desktop.sh to add LXQt alongside XFCE4.
# At the LightDM login screen the user can switch sessions.
# To test: at LightDM, click the session icon (gear/person) → pick "lxqt"
#
# If you prefer LXQt as the DEFAULT session:
#   Edit /etc/lightdm/lightdm.conf  →  user-session=lxqt
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
echo "[15-lxqt] Installing LXQt as optional session alongside XFCE4 — $(date)"

LIVE_USER="dr-i30ltz"
LIVE_HOME="/home/${LIVE_USER}"

export DEBIAN_FRONTEND=noninteractive

apt-get update -q

LXQT_PKGS=(
  lxqt-core
  lxqt-about
  lxqt-config
  lxqt-notificationd
  lxqt-panel
  lxqt-powermanagement
  lxqt-runner
  lxqt-session
  lxqt-sudo
  lxqt-themes
  pcmanfm-qt
  qterminal
  openbox
  picom
  featherpad
  lxqt-archiver
  screengrab
)

echo "[15-lxqt] Installing LXQt packages..."
apt-get install -y --no-install-recommends "${LXQT_PKGS[@]}"

# ── LXQt session config ───────────────────────────────────────────────────────
mkdir -p "${LIVE_HOME}/.config/lxqt"

cat > "${LIVE_HOME}/.config/lxqt/lxqt.conf" <<INI
[General]
icon_theme=Papirus-Dark
single_click_activate=false
theme=dark

[Qt]
style=Fusion
INI

# ── LXQt panel — minimal bottom bar ─────────────────────────────────────────
mkdir -p "${LIVE_HOME}/.config/lxqt"
cat > "${LIVE_HOME}/.config/lxqt/panel.conf" <<INI
[General]
panels=panel1

[panel1]
alignment=Left
animation-duration=0
background-color=#08080C
background-image=
custom-background-color=true
custom-font=true
edge=Bottom
font=JetBrains Mono,10,-1,5,50,0,0,0,0,0
hide-on-hover=false
hidden=false
icon-size=22
length=100
length-type=percent
lineCount=1
movable=false
opacity=240
plugins=taskbar, spacer, clock, sysstat, showdesktop
position=bottom
scrollable=false
width=100

[panel1/clock]
dateFormat=ddd d MMM
timeFormat=HH:mm
INI

# ── LXQt openbox theme ────────────────────────────────────────────────────────
mkdir -p "${LIVE_HOME}/.config/openbox"
cat > "${LIVE_HOME}/.config/openbox/lxqt-rc.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!-- Openbox config for LXQt — I30LTZ Recovery OS — 2026-09-26 -->
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>yes</animateIconify>
  </theme>
  <desktops>
    <number>2</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>Recovery</name>
      <name>Tools</name>
    </names>
  </desktops>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
    <keybind key="Super_L">
      <action name="Execute"><command>lxqt-runner</command></action>
    </keybind>
    <keybind key="C-A-t">
      <action name="Execute"><command>qterminal</command></action>
    </keybind>
    <keybind key="C-A-f">
      <action name="Execute"><command>pcmanfm-qt</command></action>
    </keybind>
  </keyboard>
</openbox_config>
XML

# Fix ownership
chown -R "${LIVE_USER}:${LIVE_USER}" "${LIVE_HOME}/.config/lxqt" \
  "${LIVE_HOME}/.config/openbox"

# ── Note for build.sh ────────────────────────────────────────────────────────
# To set LXQt as the default session, edit /etc/lightdm/lightdm.conf:
#   user-session=lxqt
# Otherwise XFCE4 remains default and LXQt is selectable at login.

echo "[15-lxqt] ── LXQt installed — selectable at LightDM login screen ──────"
echo "[15-lxqt]   To switch default: edit /etc/lightdm/lightdm.conf → user-session=lxqt"
