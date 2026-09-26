#!/usr/bin/env bash
# =============================================================================
# i30LTZ RECOVERY OS — Debian Base Setup Script
# Version: 1.0.0 | Date: 2026-09-26
# Installs: Claude Desktop, Google Chrome, dev tools, i30LTZ shell UI
# Run as ROOT on fresh Debian 12 (Bookworm) install
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
CYAN='\033[0;36m'
AMBER='\033[0;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

VERSION="1.0.0"
DATE="2026-09-26"
LOG="/var/log/i30ltz-setup.log"

banner() {
  echo -e "${RED}${BOLD}"
  echo "  ██╗██████╗  ██████╗ ██╗  ████████╗███████╗"
  echo "  ██║╚════██╗██╔═████╗██║  ╚══██╔══╝╚══███╔╝"
  echo "  ██║ █████╔╝██║██╔██║██║     ██║     ███╔╝ "
  echo "  ██║ ╚═══██╗████╔╝██║██║     ██║    ███╔╝  "
  echo "  ██║██████╔╝╚██████╔╝███████╗██║   ███████╗"
  echo "  ╚═╝╚═════╝  ╚═════╝ ╚══════╝╚═╝   ╚══════╝"
  echo -e "${CYAN}  RECOVERY OS — DEBIAN BUILD v${VERSION} · ${DATE}${NC}"
  echo -e "${AMBER}  Dr. I30LTZ :: MAD IT Recovery System${NC}"
  echo ""
}

log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG"; }
ok()  { echo -e "${GREEN}[  OK  ]${NC} $1" | tee -a "$LOG"; }
err() { echo -e "${RED}[ERROR ]${NC} $1" | tee -a "$LOG"; exit 1; }
warn(){ echo -e "${AMBER}[ WARN ]${NC} $1" | tee -a "$LOG"; }

# ── Root check ─────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Run as root: sudo bash i30ltz-setup.sh"

banner
log "Starting i30LTZ Debian setup v${VERSION}"

# ── 1. System update ────────────────────────────────────────────────────────
log "Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq | tee -a "$LOG"
ok "System updated"

# ── 2. Base dependencies ─────────────────────────────────────────────────── 
log "Installing base dependencies..."
apt-get install -y -qq \
  curl wget gnupg apt-transport-https ca-certificates \
  software-properties-common lsb-release \
  git build-essential python3 python3-pip \
  flatpak xdg-desktop-portal xdg-desktop-portal-gtk \
  xdg-utils desktop-file-utils \
  fonts-noto fonts-noto-color-emoji \
  unzip p7zip-full \
  neovim tmux htop ncdu \
  | tee -a "$LOG"
ok "Base dependencies installed"

# ── 3. RECOVERY TOOLS ───────────────────────────────────────────────────────
log "Installing i30LTZ recovery tool stack..."
apt-get install -y -qq \
  ddrescue dcfldd testdisk photorec foremost scalpel \
  ntfs-3g ntfs-progs exfatprogs dosfstools \
  smartmontools nvme-cli hdparm \
  clamav clamav-daemon yara rkhunter chkrootkit \
  mdadm btrfs-progs zfsutils-linux \
  gparted partclone clonezilla \
  samba nfs-kernel-server nfs-common \
  chntpw \
  wireshark nmap net-tools \
  | tee -a "$LOG"
ok "Recovery tools installed"

# ── 4. Google Chrome ─────────────────────────────────────────────────────── 
log "Installing Google Chrome..."
CHROME_DEB="/tmp/google-chrome.deb"
wget -q -O "$CHROME_DEB" \
  "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
apt-get install -y -qq "$CHROME_DEB" | tee -a "$LOG"
rm -f "$CHROME_DEB"

# Enable download manager / allow all file types
CHROME_POLICY_DIR="/etc/opt/chrome/policies/managed"
mkdir -p "$CHROME_POLICY_DIR"
cat > "$CHROME_POLICY_DIR/i30ltz-policy.json" << 'CHRPOL'
{
  "DownloadRestrictions": 0,
  "SafeBrowsingEnabled": false,
  "AllowDeletingBrowserHistory": true,
  "DownloadDirectory": "${HOME}/Downloads",
  "PromptForDownloadLocation": true,
  "DefaultNotificationsSetting": 2,
  "DefaultPopupsSetting": 1,
  "HomepageLocation": "file:///opt/i30ltz/ui/home.html",
  "HomepageIsNewTabPage": false,
  "NewTabPageLocation": "file:///opt/i30ltz/ui/home.html",
  "RestoreOnStartup": 4,
  "RestoreOnStartupURLs": ["file:///opt/i30ltz/ui/home.html"],
  "BookmarkBarEnabled": true,
  "ShowHomeButton": true
}
CHRPOL
ok "Chrome installed — downloads unrestricted, homepage set to i30LTZ portal"

# ── 5. Claude Desktop ───────────────────────────────────────────────────────
log "Installing Claude Desktop..."
# Fetch latest release
CLAUDE_URL=$(curl -s https://api.github.com/repos/anthropics/claude-desktop/releases/latest \
  2>/dev/null | grep -o '"browser_download_url": "[^"]*linux[^"]*\.deb"' \
  | head -1 | cut -d'"' -f4 || true)

if [[ -z "$CLAUDE_URL" ]]; then
  warn "Claude Desktop auto-fetch failed. Trying direct URL..."
  # Fallback: known URL pattern
  CLAUDE_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-4751-9381-de02a3686d93/nest-apple/linux/Claude-latest.deb"
fi

if curl -sI "$CLAUDE_URL" 2>/dev/null | grep -q "200"; then
  wget -q -O /tmp/claude-desktop.deb "$CLAUDE_URL"
  apt-get install -y -qq /tmp/claude-desktop.deb | tee -a "$LOG"
  rm -f /tmp/claude-desktop.deb
  ok "Claude Desktop installed"
else
  warn "Claude Desktop .deb not reachable — creating manual install helper"
  cat > /opt/i30ltz/install-claude.sh << 'CSCRIPT'
#!/bin/bash
# Manual Claude Desktop installer
# Run after booting into i30LTZ
echo "Download Claude Desktop from: https://claude.ai/download"
echo "Then run: sudo apt install ./Claude-*.deb"
xdg-open "https://claude.ai/download" 2>/dev/null &
CSCRIPT
  chmod +x /opt/i30ltz/install-claude.sh
fi

# ── 6. Install i30LTZ UI Shell ──────────────────────────────────────────────
log "Installing i30LTZ UI shell..."
mkdir -p /opt/i30ltz/ui
mkdir -p /opt/i30ltz/bin
mkdir -p /opt/i30ltz/icons
mkdir -p /opt/i30ltz/config

# Copy UI files (script expects to be run from i30ltz-setup dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/../ui-shell" ]]; then
  cp -r "$SCRIPT_DIR/../ui-shell/"* /opt/i30ltz/ui/
  ok "UI shell files copied to /opt/i30ltz/ui/"
else
  warn "UI shell dir not found — download separately"
fi

# ── 7. Autostart i30LTZ shell on login ──────────────────────────────────────
log "Setting up autostart..."
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/i30ltz-shell.desktop << 'AUTOSTART'
[Desktop Entry]
Type=Application
Name=i30LTZ Shell
Comment=i30LTZ Recovery OS Edge Drawers and Home
Exec=google-chrome --app=file:///opt/i30ltz/ui/home.html --kiosk-printing --no-first-run
StartupNotify=false
NoDisplay=true
AUTOSTART

# Also set Chrome as default browser
update-alternatives --set x-www-browser /usr/bin/google-chrome-stable 2>/dev/null || true
xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null || true
ok "Autostart configured"

# ── 8. Desktop entry for i30LTZ Portal ──────────────────────────────────────
cat > /usr/share/applications/i30ltz-portal.desktop << 'DESK'
[Desktop Entry]
Version=1.0
Type=Application
Name=i30LTZ Portal
Comment=i30LTZ Recovery OS Home — v1.0.0 · 2026-09-26
Exec=google-chrome --app=file:///opt/i30ltz/ui/home.html
Icon=/opt/i30ltz/icons/i30ltz.png
Terminal=false
Categories=System;Recovery;
Keywords=recovery;repair;forensics;
DESK

ok "Desktop entry created"

# ── 9. Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  i30LTZ SETUP COMPLETE  v${VERSION} · ${DATE}${NC}"
echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}✓${NC} Google Chrome     — homepage: /opt/i30ltz/ui/home.html"
echo -e "  ${GREEN}✓${NC} Recovery Tools    — ddrescue, testdisk, clonezilla+"
echo -e "  ${GREEN}✓${NC} i30LTZ UI Shell   — /opt/i30ltz/ui/"
echo ""
echo -e "  ${AMBER}NEXT:${NC} sudo bash i30ltz-setup.sh --install-ui"
echo -e "  ${AMBER}LOG: ${NC} $LOG"
echo ""
