#!/usr/bin/env bash
# =============================================================================
# I30LTZ Recovery OS — boot a built image in a UEFI VM (safe: works on a copy)
# v0.1.0 · 2026-10-01
#   sudo bash test-vm.sh out/v0.1.0_2026-10-01            # window (GTK)
#   sudo bash test-vm.sh out/v0.1.0_2026-10-01 --serial   # text-only, serial log
# Your real drives are never attached to the VM.
# =============================================================================
set -euo pipefail
dir="${1:-}"; mode="${2:-}"
img=""
for f in "$dir"/i30ltz-recovery-os_*.raw; do   # the whole-disk image, not the split partitions
  [[ "${f##*/}" =~ ^i30ltz-recovery-os_[0-9.]+\.raw$ ]] && img="$f"
done
[[ -n "$img" ]] || { echo "usage: sudo bash test-vm.sh <out/vX_DATE dir> [--serial]"; exit 1; }
work=/var/tmp/i30ltz-vm; mkdir -p "$work"
code=""; for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do [[ -f $c ]] && { code=$c; break; }; done
[[ -n "$code" ]] || { echo "OVMF missing: sudo apt install ovmf"; exit 1; }
cp -f "${code/CODE/VARS}" "$work/vars.fd"
echo "copying image (the original stays untouched)…"
cp --sparse=always -f "$img" "$work/disk.raw"
truncate -s +8G "$work/disk.raw"     # room like a real drive; root grows on install, not here
kvm=(); [[ -w /dev/kvm ]] && kvm=(-enable-kvm -cpu host)
display=(-vga virtio -display gtk); [[ "$mode" == --serial ]] && display=(-nographic)
exec qemu-system-x86_64 "${kvm[@]}" -machine q35 -smp 2 -m 3072 \
  -drive if=pflash,format=raw,readonly=on,file="$code" \
  -drive if=pflash,format=raw,file="$work/vars.fd" \
  -drive file="$work/disk.raw",if=virtio,format=raw \
  -nic user,model=virtio-net-pci "${display[@]}"
