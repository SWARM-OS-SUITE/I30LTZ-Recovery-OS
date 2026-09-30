#!/usr/bin/env bash
# =============================================================================
# I30LTZ Recovery OS — First Boot · verify (read-only, changes nothing)
# Version: 2.0.0 | Date: 2026-09-30
#   sudo bash verify.sh
# =============================================================================
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/lib/common.sh
source "$KIT_DIR/../common/lib/common.sh"

pass=0; fail=0
check() {  # check "label" command...
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; ((pass++))
  else printf '%s[ MISS ]%s %s\n' "$C_RED" "$C_NC" "$label"; ((fail++)); fi
}

printf '%s%sI30LTZ Recovery OS verify v2.0.0 · 2026-09-30%s\n' "$C_RED" "$C_BOLD" "$C_NC"

step "Security"
check "firewall active, deny incoming"   bash -c "ufw status verbose | grep -q 'Status: active' && ufw status verbose | grep -q 'deny (incoming)'"
check "AppArmor enabled"                 aa-enabled
check "automatic security updates"       systemctl is-enabled unattended-upgrades
check "kernel hardening loaded"          bash -c '[[ $(sysctl -n kernel.kptr_restrict) == 2 ]]'
check "core dumps disabled"              test -f /etc/systemd/coredump.conf.d/60-firstboot.conf
check "SSH off, or key-only"             bash -c '! systemctl is-active -q ssh || grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config.d/60-firstboot-hardening.conf'

step "Performance + graphics"
check "Vulkan driver present"            bash -c 'vulkaninfo --summary 2>/dev/null | grep -q deviceName'
check "OpenGL renderer is hardware"      bash -c 'glxinfo -B 2>/dev/null | grep "OpenGL renderer" | grep -vqi llvmpipe'
check "zram swap active"                 bash -c 'swapon --show=NAME --noheadings | grep -q zram'
check "fstrim timer enabled"             systemctl is-enabled fstrim.timer

step "I30LTZ Recovery · MAD IT"
check "OS identity /etc/i30ltz/release"  test -f /etc/i30ltz/release
check "cases store is private (2770)"    bash -c '[[ $(stat -c %a /var/lib/i30ltz/cases) == 2770 ]]'
check "ddrescue"                         command -v ddrescue
check "testdisk + photorec"              bash -c 'command -v testdisk && command -v photorec'
check "SMART tools"                      command -v smartctl
check "write-blocker helper"             command -v i30ltz-writeblock

printf '\n%s%d passed%s · %s%d missing%s\n' "$C_GREEN" "$pass" "$C_NC" "$C_RED" "$fail" "$C_NC"
((fail == 0)) || echo "Re-run the matching module:  sudo bash first-boot.sh --only 50-recovery-mad-it"
