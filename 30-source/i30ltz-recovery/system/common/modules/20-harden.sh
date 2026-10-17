# shellcheck shell=bash
# about: firewall, AppArmor, kernel hardening, SSH off-by-default, lock screen
# Ubuntu first-boot shared module v2.0.0 · 2026-09-30

apt_install ufw apparmor apparmor-utils

# ── Firewall: nothing gets in unless you ask ───────────────────────────────
run ufw --force default deny incoming
run ufw --force default allow outgoing
run ufw logging low
run ufw --force enable
ok "firewall: deny incoming, allow outgoing"

# ── AppArmor ───────────────────────────────────────────────────────────────
run systemctl enable --now apparmor.service
ok "AppArmor: enabled"

# ── Kernel + network hardening (gaming/coding friendly) ────────────────────
write_file /etc/sysctl.d/60-firstboot-hardening.conf 0644 <<'CFG'
# first-boot kit v2.0.0 · 2026-09-30
# Hide kernel pointers + logs from normal users
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.kexec_load_disabled = 1
# ptrace: parent-only (debuggers still work via sudo or launching under gdb)
kernel.yama.ptrace_scope = 1
# Filesystem link protections
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0
# Network: no spoofing, no redirects, no source routing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1
CFG
run sysctl --system >/dev/null 2>&1 || warn "sysctl reported unknown keys (settings still load at next boot)"

# ── No core dumps leaking memory to disk ───────────────────────────────────
write_file /etc/security/limits.d/60-firstboot-nocore.conf 0644 <<'CFG'
# first-boot kit v2.0.0 · 2026-09-30
* hard core 0
CFG
write_file /etc/systemd/coredump.conf.d/60-firstboot.conf 0644 <<'CFG'
# first-boot kit v2.0.0 · 2026-09-30
[Coredump]
Storage=none
ProcessSizeMax=0
CFG

# ── Home folders private (other accounts can't read yours) ─────────────────
[[ -n "$TARGET_HOME" ]] && run chmod 0750 "$TARGET_HOME"
if [[ -f /etc/adduser.conf ]] && ! grep -q '^DIR_MODE=0750' /etc/adduser.conf; then
  backup_file /etc/adduser.conf
  run sed -i 's/^#\?DIR_MODE=.*/DIR_MODE=0750/' /etc/adduser.conf
fi

# ── Remote login: OFF unless --enable-ssh ──────────────────────────────────
if [[ "$ENABLE_SSH" == 1 ]]; then
  [[ -n "$TARGET_USER" ]] || die "--enable-ssh needs --user NAME (the only account allowed to log in)"
  apt_install openssh-server fail2ban
  write_file /etc/ssh/sshd_config.d/60-firstboot-hardening.conf 0644 <<'CFG'
# first-boot kit v2.0.0 · 2026-09-30 — keys only, no root
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
AllowUsers __USER__
CFG
  [[ "$DRY_RUN" == 1 ]] || sed -i "s/__USER__/$TARGET_USER/" /etc/ssh/sshd_config.d/60-firstboot-hardening.conf
  if [[ ! -s "$TARGET_HOME/.ssh/authorized_keys" ]]; then
    warn "SSH is key-only but $TARGET_HOME/.ssh/authorized_keys is empty — add your key before logging in remotely"
  fi
  run sshd -t
  run systemctl enable --now ssh fail2ban
  run ufw limit OpenSSH
  ok "SSH: key-only, rate-limited, fail2ban on"
elif systemctl is-enabled ssh >/dev/null 2>&1; then
  run systemctl disable --now ssh
  ok "SSH: was on — turned off (use --enable-ssh if you need it)"
else
  ok "SSH: not running (good)"
fi

# ── Desktop: auto lock + no guest session ──────────────────────────────────
if [[ -d /etc/dconf ]] || have gnome-shell; then
  write_file /etc/dconf/db/local.d/60-firstboot-security 0644 <<'CFG'
# first-boot kit v2.0.0 · 2026-09-30
[org/gnome/desktop/screensaver]
lock-enabled=true
lock-delay=uint32 0
[org/gnome/desktop/session]
idle-delay=uint32 600
[org/gnome/desktop/privacy]
remember-recent-files=true
remove-old-temp-files=true
remove-old-trash-files=true
old-files-age=uint32 30
report-technical-problems=false
send-software-usage-stats=false
CFG
  write_file /etc/dconf/profile/user 0644 <<'CFG'
user-db:user
system-db:local
CFG
  have dconf && run dconf update
  ok "desktop: locks after 10 min idle, telemetry off"
fi
