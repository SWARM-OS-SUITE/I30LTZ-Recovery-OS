#!/usr/bin/env bash
# =============================================================================
# SWARM_OS Suite · Dev Workstation — verify (read-only, changes nothing)
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

printf '%s%sSWARM_OS Suite Dev Workstation verify v2.0.0 · 2026-09-30%s\n' "$C_CYAN" "$C_BOLD" "$C_NC"

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
check "game-ready max_map_count"         bash -c '(( $(sysctl -n vm.max_map_count) > 1000000 ))'

step "Dev workstation"
check "role file /etc/suite-dev/release" test -f /etc/suite-dev/release
check "rust toolchain"                   bash -c 'command -v cargo || ls /home/*/.cargo/bin/cargo'
check "QEMU for ISO boot tests"          command -v qemu-system-x86_64
check "UEFI firmware (OVMF)"             bash -c 'ls /usr/share/OVMF/OVMF_CODE*.fd'
check "gamemode"                         command -v gamemoded

step "Recovery test bench (MAD IT tools)"
check "ddrescue"                         command -v ddrescue
check "testdisk + photorec"              bash -c 'command -v testdisk && command -v photorec'
check "SMART tools"                      command -v smartctl
check "write-blocker helper"             command -v i30ltz-writeblock

step "Not pretending to be either OS"
check "no SWARM_OS identity here"        test ! -e /etc/swarm_os/release
check "no I30LTZ OS identity here"       test ! -e /etc/i30ltz/release

printf '\n%s%d passed%s · %s%d missing%s\n' "$C_GREEN" "$pass" "$C_NC" "$C_RED" "$fail" "$C_NC"
((fail == 0)) || echo "Upgrading from v1.0.0? Run:  sudo bash migrate-from-v1.sh"
