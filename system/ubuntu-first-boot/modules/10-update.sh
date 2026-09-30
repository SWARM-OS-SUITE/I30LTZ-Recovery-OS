# shellcheck shell=bash
# about: full upgrade, automatic security updates, firmware updates
# SWARM_OS Suite · Ubuntu First Boot v1.0.0 · 2026-09-30

run apt-get update
apt_install software-properties-common
enable_component universe
wants swarm && enable_component multiverse   # Steam, Intel media codecs
enable_component restricted

[[ "$APT_DIRTY" == 1 ]] && run apt-get update
run env DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
APT_DIRTY=0
apt_install unattended-upgrades apt-listchanges needrestart fwupd

write_file /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'CFG'
// SWARM_OS first boot v1.0.0 · 2026-09-30
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CFG

write_file /etc/apt/apt.conf.d/52swarm-unattended 0644 <<'CFG'
// SWARM_OS first boot v1.0.0 · 2026-09-30 — security fixes install themselves
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
CFG

run systemctl enable --now unattended-upgrades.service
run systemctl enable --now fwupd-refresh.timer || warn "fwupd-refresh.timer not available"
if [[ "$DRY_RUN" != 1 ]]; then
  fwupdmgr refresh --force >/dev/null 2>&1 || true
  if fwupdmgr get-updates >/dev/null 2>&1; then
    warn "firmware updates available — review with: sudo fwupdmgr update"
  else ok "firmware: nothing pending"; fi
fi
