# shellcheck shell=bash
# about: SWARM_OS builder — Arch container (mkarchiso), QEMU test boots, disk-safety helper
# I30LTZ Recovery OS first boot v2.1.0 · 2026-10-01
#
# One PC: Recovery OS (this external drive) builds SWARM_OS for the internal
# NVMe. A broken SWARM_OS build can never strand you, because the builder
# lives on a different drive. Nothing here ever writes to the internal disk.

apt_install podman qemu-system-x86 qemu-utils ovmf
[[ -n "$TARGET_USER" ]] && getent group kvm >/dev/null && run usermod -aG kvm "$TARGET_USER"

run install -d -o root -g i30ltz -m 2770 /var/lib/i30ltz/swarm-build \
  /var/lib/i30ltz/swarm-build/out /var/lib/i30ltz/swarm-build/work /var/lib/i30ltz/swarm-build/vm

# ── swarm-build: archiso profile → SWARM_OS ISO, built inside Arch ─────────
write_file /opt/i30ltz/bin/swarm-build 0755 <<'SH'
#!/usr/bin/env bash
# SWARM_OS builder v1.0.0 · 2026-10-01 — runs mkarchiso inside an Arch container
# usage: swarm-build <archiso-profile-dir> [out-dir]
#   e.g. swarm-build ~/SWARM_OS/30-source/swarm-os/profile
set -euo pipefail
profile="${1:-}"; out="${2:-/var/lib/i30ltz/swarm-build/out}"
work=/var/lib/i30ltz/swarm-build/work
if [[ -z "$profile" || ! -f "$profile/profiledef.sh" ]]; then
  echo "usage: swarm-build <archiso-profile-dir> [out-dir]"
  echo "       (the profile dir is the one that contains profiledef.sh)"
  exit 1
fi
profile="$(realpath "$profile")"; mkdir -p "$out"; out="$(realpath "$out")"
free_gb=$(df -BG --output=avail "$work" | tail -1 | tr -dc '0-9')
(( free_gb >= 20 )) || { echo "need 20G free in $work (have ${free_gb}G)"; exit 1; }
stamp="$(date +%Y-%m-%d_%H%M%S)"
echo "🟣 SWARM_OS build · $stamp · profile=$profile → $out"
sudo rm -rf "${work:?}"/*
sudo podman run --rm --privileged \
  -v "$profile":/profile:ro -v "$out":/out -v "$work":/work \
  -v swarm-pacman-cache:/var/cache/pacman/pkg \
  docker.io/library/archlinux:latest \
  bash -c 'pacman -Syu --noconfirm --needed archiso && mkarchiso -v -w /work -o /out /profile'
sudo rm -rf "${work:?}"/*
sudo chown -R "$(id -u):$(id -g)" "$out"
latest="$(ls -t "$out"/*.iso | head -1)"
( cd "$out" && sha256sum "$(basename "$latest")" > "$(basename "$latest").sha256" )
echo "✅ built: $latest"
echo "   test it:  swarm-test-iso \"$latest\""
SH

# ── swarm-test-iso: boot an ISO in a UEFI VM (never touches real disks) ────
write_file /opt/i30ltz/bin/swarm-test-iso 0755 <<'SH'
#!/usr/bin/env bash
# SWARM_OS ISO test boot v1.0.0 · 2026-10-01 — UEFI VM with a throwaway disk
# usage: swarm-test-iso <file.iso> [--ram 4096] [--fresh-disk]
set -euo pipefail
iso="${1:-}"; shift || true
ram=4096; fresh=0
while (($#)); do case "$1" in --ram) ram="$2"; shift 2 ;; --fresh-disk) fresh=1; shift ;; *) echo "unknown: $1"; exit 1 ;; esac; done
[[ -f "$iso" ]] || { echo "usage: swarm-test-iso <file.iso> [--ram MB] [--fresh-disk]"; exit 1; }
vm=/var/lib/i30ltz/swarm-build/vm
code=""; for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do [[ -f $c ]] && { code=$c; break; }; done
vars_src="${code/CODE/VARS}"
[[ -n "$code" && -f "$vars_src" ]] || { echo "OVMF firmware missing: sudo apt install ovmf"; exit 1; }
[[ -f $vm/vars.fd ]] || cp "$vars_src" "$vm/vars.fd"
if [[ $fresh == 1 || ! -f $vm/swarm-test.qcow2 ]]; then
  rm -f "$vm/swarm-test.qcow2"; qemu-img create -q -f qcow2 "$vm/swarm-test.qcow2" 40G
fi
kvm=(); [[ -w /dev/kvm ]] && kvm=(-enable-kvm -cpu host) || echo "⚠ no /dev/kvm access — slow mode (log out/in after first boot kit)"
echo "🟣 test boot: $iso · ${ram}MB · virtual disk $vm/swarm-test.qcow2 (your real drives are NOT attached)"
exec qemu-system-x86_64 "${kvm[@]}" -machine q35 -smp 2 -m "$ram" \
  -drive if=pflash,format=raw,readonly=on,file="$code" \
  -drive if=pflash,format=raw,file="$vm/vars.fd" \
  -drive file="$vm/swarm-test.qcow2",if=virtio,format=qcow2 \
  -cdrom "$iso" -boot order=d,menu=on \
  -vga virtio -display gtk -nic user,model=virtio-net-pci
SH

# ── i30ltz-disks: which disk is which (before ANY install to the NVMe) ─────
write_file /opt/i30ltz/bin/i30ltz-disks 0755 <<'SH'
#!/usr/bin/env bash
# Dr. I30LTZ disk map v1.0.0 · 2026-10-01 — read-only
set -euo pipefail
root_src="$(findmnt -no SOURCE /)"
root_disk="/dev/$(lsblk -no PKNAME "$(readlink -f "$root_src")" 2>/dev/null | tail -1)"
[[ "$root_disk" == /dev/ ]] && root_disk="(unknown — LVM/LUKS: see TREE below)"
echo "🔴 Recovery OS is running from: $root_disk   (DO NOT install SWARM_OS here)"
echo
field() { sed -n "s/.*$1=\"\([^\"]*\)\".*/\1/p" <<<"$2"; }
printf '%-14s %-7s %-6s %-4s %s\n' DISK SIZE TRAN USB? MODEL
lsblk -dpnP -o NAME,SIZE,TRAN,RM,MODEL | while IFS= read -r line; do
  name=$(field NAME "$line"); size=$(field SIZE "$line"); tran=$(field TRAN "$line")
  rm=$(field RM "$line"); model=$(field MODEL "$line")
  tag=""; [[ "$tran" == nvme || "$name" == /dev/nvme* ]] && tag="  ← internal NVMe (SWARM_OS target)"
  [[ "$name" == "$root_disk" ]] && tag="  ← THIS Recovery OS drive"
  printf '%-14s %-7s %-6s %-4s %s%s\n' "$name" "$size" "${tran:--}" "$([[ $rm == 1 || $tran == usb ]] && echo yes || echo no)" "${model:--}" "$tag"
done
echo; echo "TREE:"; lsblk -po NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
SH

for t in swarm-build swarm-test-iso i30ltz-disks; do
  run ln -sf "/opt/i30ltz/bin/$t" "/usr/local/bin/$t"
done
ok "SWARM_OS builder ready: swarm-build · swarm-test-iso · i30ltz-disks"
