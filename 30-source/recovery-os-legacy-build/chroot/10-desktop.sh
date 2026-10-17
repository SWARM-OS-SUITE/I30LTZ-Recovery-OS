#!/usr/bin/env bash
# I30LTZ Recovery OS — Stage 10: XFCE4 Desktop (minimal, fast)
# Version: 1.0.0  |  2026-09-25
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "DR. I30LTZ  |  10-desktop.sh starting..."

# ── Display server ───────────────────────────────────────────
apt-get install -y --no-install-recommends \
  xorg xserver-xorg x11-xserver-utils xinit \
  xfce4 xfce4-terminal xfce4-screenshooter \
  xfce4-taskmanager xfce4-power-manager \
  xfconf xfce4-session xfce4-settings \
  thunar thunar-volman \
  xdg-utils xdg-user-dirs \
  lightdm lightdm-gtk-greeter \
  lightdm-gtk-greeter-settings \
  papirus-icon-theme \
  fonts-noto-core fonts-noto-mono fonts-ubuntu \
  fonts-jetbrains-mono \
  arc-theme \
  picom \
  dunst \
  rofi \
  gvfs gvfs-backends \
  network-manager network-manager-gnome \
  pulseaudio pavucontrol \
  file-roller \
  xarchiver \
  mousepad \
  ristretto \
  gpicview

# ── LightDM greeter config ───────────────────────────────────
mkdir -p /etc/lightdm
cat > /etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
autologin-guest=false
autologin-user=dr-i30ltz
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
EOF

cat > /etc/lightdm/lightdm-gtk-greeter.conf << 'EOF'
[greeter]
background=#08080C
theme-name=Arc-Dark
icon-theme-name=Papirus-Dark
font-name=JetBrains Mono 11
indicators=~host;~spacer;~clock;~spacer;~session;~power
clock-format=%A %B %d  |  %H:%M
panel-position=bottom
EOF

# ── XFCE autostart directory ─────────────────────────────────
mkdir -p /home/dr-i30ltz/.config/autostart
mkdir -p /home/dr-i30ltz/.config/xfce4/xfconf/xfce-perchannel-xml

# ── XFCE panel config ─────────────────────────────────────────
cat > /home/dr-i30ltz/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="rgba1" type="array">
            <value type="double" value="0.031373"/>
            <value type="double" value="0.031373"/>
            <value type="double" value="0.047059"/>
            <value type="double" value="1.000000"/>
          </property>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF

# ── GTK dark theme ───────────────────────────────────────────
mkdir -p /home/dr-i30ltz/.config/gtk-3.0
cat > /home/dr-i30ltz/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrains Mono 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-application-prefer-dark-theme=1
EOF

# ── Terminal defaults ────────────────────────────────────────
mkdir -p /home/dr-i30ltz/.config/xfce4/terminal
cat > /home/dr-i30ltz/.config/xfce4/terminal/terminalrc << 'EOF'
[Configuration]
FontName=JetBrains Mono 11
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=120x35
MiscInheritGeometry=FALSE
MiscMenubarDefault=FALSE
MiscMouseAutohide=FALSE
MiscToolbarDefault=FALSE
MiscConfirmClose=FALSE
ColorForeground=#E0E0E4
ColorBackground=#08080C
ColorCursor=#BA0C2F
ColorPalette=#1C1C1C;#BA0C2F;#00C850;#FFA500;#3A7BD5;#8E44AD;#00BCD4;#E0E0E4;#2A2A2A;#FF1A47;#00E676;#FFB74D;#5B9BD5;#AA5FD3;#4DD0E1;#FFFFFF
EOF

# ── Fix ownership ────────────────────────────────────────────
chown -R dr-i30ltz:dr-i30ltz /home/dr-i30ltz/

echo "10-desktop.sh ✓ complete"
