# shellcheck shell=bash
# about: checks Ubuntu version, disk, network, Secure Boot, disk encryption
# Ubuntu first-boot shared module v2.0.0 · 2026-09-30

[[ -r /etc/os-release ]] || die "no /etc/os-release — is this Ubuntu?"
# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID:-}" == ubuntu || "${ID_LIKE:-}" == *ubuntu* ]] || die "this kit targets Ubuntu (found: ${PRETTY_NAME:-unknown})"
case "${VERSION_ID:-}" in
  24.04|26.04) ok "Ubuntu ${VERSION_ID} LTS — supported" ;;
  *) warn "Ubuntu ${VERSION_ID:-?} is not an LTS this kit was tested on (24.04 / 26.04)" ;;
esac

free_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
((free_gb >= 15)) && ok "free space on /: ${free_gb}G" || warn "only ${free_gb}G free on / — this kit wants 15G+"

if getent ahosts archive.ubuntu.com >/dev/null 2>&1; then ok "network: package mirror reachable"
else die "no network — plug in ethernet or join Wi-Fi, then re-run"; fi

if have mokutil; then
  sb=$(mokutil --sb-state 2>/dev/null || true)
  [[ "$sb" == *enabled* ]] && ok "Secure Boot: enabled" || warn "Secure Boot is OFF — turn it on in firmware setup for boot-chain protection"
fi

if lsblk -o TYPE 2>/dev/null | grep -q crypt; then ok "disk encryption (LUKS) detected"
else warn "no LUKS encryption found — reinstall with 'Encrypt disk' if this PC ever leaves your room"; fi

if lspci 2>/dev/null | grep -Ei 'vga|3d|display' | grep -qi intel; then GPU_VENDOR=intel
elif lspci 2>/dev/null | grep -Ei 'vga|3d|display' | grep -qiE 'amd|ati'; then GPU_VENDOR=amd
else GPU_VENDOR=unknown; fi
export GPU_VENDOR
info "graphics: ${GPU_VENDOR} ($(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -1 | cut -d: -f3- | xargs || echo 'not detected'))"
