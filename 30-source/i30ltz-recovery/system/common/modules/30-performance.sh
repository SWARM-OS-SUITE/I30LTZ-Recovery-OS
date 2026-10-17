# shellcheck shell=bash
# about: integrated-graphics drivers, Vulkan, video decode, zram (+ gaming tuning on the workstation)
# Ubuntu first-boot shared module v2.0.0 · 2026-09-30

# ── Graphics stack (Mesa = best open driver for Intel/AMD iGPUs) ───────────
apt_install mesa-utils mesa-vulkan-drivers vulkan-tools libgl1-mesa-dri
case "${GPU_VENDOR:-unknown}" in
  intel) apt_optional intel-media-va-driver-non-free intel-gpu-tools vainfo ;;
  amd)   apt_optional mesa-va-drivers radeontop vainfo ;;
  *)     apt_optional mesa-va-drivers vainfo ;;
esac
# 32-bit Vulkan/GL so Steam + Proton games run
if [[ "${FEATURE_GAMING:-0}" == 1 ]]; then
  if ! dpkg --print-foreign-architectures | grep -q i386; then
    run dpkg --add-architecture i386
    run apt-get update
  fi
  apt_optional mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386
fi
ok "graphics: Mesa + Vulkan + hardware video decode (${GPU_VENDOR:-unknown})"

# ── Power / CPU: let power-profiles-daemon pick; gamemode boosts on demand ──
apt_optional power-profiles-daemon thermald
run systemctl enable --now thermald 2>/dev/null || true

# ── zram: compressed RAM swap — big win on iGPU laptops sharing memory ─────
apt_optional systemd-zram-generator
write_file /etc/systemd/zram-generator.conf 0644 <<'CFG'
# first-boot kit v2.0.0 · 2026-09-30
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
CFG

# High swappiness only makes sense when swap is RAM (zram), not the SSD.
if pkg_installed systemd-zram-generator || [[ "$DRY_RUN" == 1 ]]; then
  ZRAM_TUNING=$'vm.swappiness = 150\nvm.page-cluster = 0'
else
  ZRAM_TUNING='# zram not installed — kernel swap defaults kept'
  warn "zram generator unavailable — using default swap behaviour"
fi

if [[ "${FEATURE_GAMING:-0}" == 1 ]]; then
  GAMING_TUNING=$'# Many modern games (Proton/DXVK) need a large map count\nvm.max_map_count = 2147483642'
else
  GAMING_TUNING='# no gaming tuning on this machine'
fi

write_file /etc/sysctl.d/61-firstboot-performance.conf 0644 <<CFG
# first-boot kit v2.0.0 · 2026-09-30
${GAMING_TUNING}
# Prefer zram over dropping file cache; keep desktop snappy
${ZRAM_TUNING}
vm.vfs_cache_pressure = 50
# Keep writeback smooth (no multi-second stalls when copying big images)
vm.dirty_background_bytes = 67108864
vm.dirty_bytes = 268435456
CFG
run sysctl --system >/dev/null 2>&1 || warn "sysctl reported unknown keys (settings still load at next boot)"

# ── SSD health ─────────────────────────────────────────────────────────────
run systemctl enable --now fstrim.timer
ok "performance: zram(zstd), fstrim weekly$([[ ${FEATURE_GAMING:-0} == 1 ]] && echo ", game-ready vm tuning")"
