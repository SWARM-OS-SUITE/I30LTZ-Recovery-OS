# i30LTZ Recovery OS — Debian Build Guide
**Version:** 1.0.0 | **Date:** 2026-09-26  
**Dr. I30LTZ :: MAD IT Recovery System**

---

## FOLDER LAYOUT

```
/opt/i30ltz/
├── ui/
│   ├── home.html              ← HOME PORTAL (app grid + drawers)
│   └── i30ltz-dashboard-v2.3.0.html
├── bin/                       ← Custom scripts
├── icons/                     ← App icons
└── config/                    ← Config files

/etc/opt/chrome/policies/managed/
└── i30ltz-policy.json         ← Chrome policy (homepage, downloads)

/etc/xdg/autostart/
└── i30ltz-shell.desktop       ← Autostart portal on login
```

---

## QUICK INSTALL (Debian 12 Bookworm)

```bash
# 1. Get fresh Debian 12
# Download: https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd/

# 2. Clone this setup to target machine
scp -r i30ltz/ user@i30ltz-machine:~/

# 3. Run setup as root
cd ~/i30ltz/debian-setup
chmod +x i30ltz-setup.sh
sudo bash i30ltz-setup.sh

# 4. Install Claude Desktop manually if auto-fetch fails
# Visit: https://claude.ai/download
# Then: sudo apt install ~/Downloads/Claude-*.deb

# 5. Copy UI to /opt
sudo cp -r ~/i30ltz/ui-shell/* /opt/i30ltz/ui/

# 6. Open portal
google-chrome file:///opt/i30ltz/ui/home.html
```

---

## CHROME SETTINGS APPLIED

| Setting | Value |
|---------|-------|
| Homepage | `/opt/i30ltz/ui/home.html` |
| New Tab | Same |
| Downloads | UNRESTRICTED (DownloadRestrictions: 0) |
| SafeBrowsing | OFF (forensics tools flag as malware) |
| PromptForDownload | ON |
| Download Dir | `~/Downloads` |

---

## EDGE DRAWERS

| Action | Trigger |
|--------|---------|
| Left drawer (App Launcher) | Hover left edge OR click "⬡ APPS" OR `Ctrl+A` |
| Right drawer (Utilities) | Hover right edge OR click "⚙ UTILS" OR `Ctrl+U` |
| Close drawers | `Esc` or click backdrop |

---

## RECOVERY TOOLS INSTALLED

- `ddrescue`, `dcfldd` — Drive imaging with error recovery
- `testdisk`, `photorec` — Partition/file recovery
- `foremost`, `scalpel` — File carving
- `smartmontools`, `nvme-cli` — Drive health
- `clamav`, `yara`, `rkhunter`, `chkrootkit` — Security scanning
- `clonezilla`, `partclone` — Disk cloning
- `gparted` — Partition management
- `chntpw` — Windows password reset
- `samba`, `nfs-kernel-server` — Network shares
- `wireshark`, `nmap` — Network forensics
- `btrfs-progs`, `zfsutils-linux`, `mdadm` — RAID/filesystem

---

## NEXT STEPS

- [ ] Confirm base OS choice: keep EndeavourOS/sdb4 OR fresh Debian install
- [ ] Upload `drbotlz4k.png` to replace SVG avatar in dashboard
- [ ] Wire OpenRouter API key into dashboard (⚙ API KEY button)
- [ ] Set up i30ltz-brains partition as persistent memory store
- [ ] Configure Samba share for recovery work across LAN

---

*i30LTZ Recovery OS — Part of SWARM OS Suite*  
*Dr. I30LTZ (MAD IT) · LUCILLE ecosystem · 2026-09-26*
