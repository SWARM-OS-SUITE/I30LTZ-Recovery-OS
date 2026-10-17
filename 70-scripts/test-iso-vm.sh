#!/usr/bin/env bash
# Boot an ISO in QEMU on the Debian dev machine (UEFI by default, KVM if available).
# Guest writes go only to a scratch qcow2 on the OS's own build partition; no
# real disk is ever attached.
#
# Usage: test-iso-vm.sh [swarm|recovery] [--iso FILE] [--bios] [--headless]
#                       [--fresh] [--no-disk] [--ram MB] [--cpus N]
#   swarm|recovery  picks the newest ISO on Ventoy for that OS (default: swarm)
#   --iso FILE      boot this ISO instead
#   --bios          legacy BIOS boot instead of UEFI
#   --headless      no window; serial console in this terminal (Ctrl+A X quits)
#   --fresh         delete the scratch disk and UEFI vars first
#   --no-disk       live boot only, no scratch disk
set -euo pipefail

OS=swarm ISO="" BIOS=0 HEADLESS=0 FRESH=0 DISK=1 RAM=4096 CPUS=4
while (( $# )); do
  case "$1" in
    swarm|recovery) OS=$1; shift ;;
    --iso) ISO=${2:?missing ISO path}; shift 2 ;;
    --bios) BIOS=1; shift ;;
    --headless) HEADLESS=1; shift ;;
    --fresh) FRESH=1; shift ;;
    --no-disk) DISK=0; shift ;;
    --ram) RAM=${2:?}; shift 2 ;;
    --cpus) CPUS=${2:?}; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done
[[ $EUID != 0 ]] || { echo "Run as your normal user, not sudo." >&2; exit 1; }

case "$OS" in
  swarm)    ISO_DIR=/mnt/ventoy/ISO/SWARM_OS;    VM_DIR=/mnt/swarmbuild/80-vm/iso-test ;;
  recovery) ISO_DIR=/mnt/ventoy/ISO/recovery-os; VM_DIR=/mnt/recoverybuild/80-vm/iso-test ;;
esac

if [[ -z $ISO ]]; then
  ISO=$(ls -t "$ISO_DIR"/*.iso 2>/dev/null | head -n1 || true)
  [[ -n $ISO ]] || { echo "No ISO found in $ISO_DIR (is Ventoy mounted at /mnt/ventoy?)" >&2; exit 1; }
fi
[[ -f $ISO ]] || { echo "Missing ISO: $ISO" >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "Install: sudo apt install qemu-system-x86 qemu-utils ovmf" >&2; exit 1; }

mkdir -p "$VM_DIR"
exec 9>"$VM_DIR/instance.lock"
flock -n 9 || { echo "A $OS test VM is already running." >&2; exit 1; }
(( ! FRESH )) || rm -f "$VM_DIR/disk.qcow2" "$VM_DIR/OVMF_VARS.fd"

ACCEL=(-accel tcg -cpu max)
[[ -w /dev/kvm ]] && ACCEL=(-accel kvm -cpu host)

ARGS=(-name "$OS ISO test" "${ACCEL[@]}" -m "$RAM" -smp "$CPUS"
      -drive "file=$ISO,media=cdrom,readonly=on,format=raw"
      -boot order=d,menu=on
      -device virtio-net-pci,netdev=n0 -netdev user,id=n0
      -device qemu-xhci -device usb-tablet)

if (( ! BIOS )); then
  CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
  [[ -f $CODE ]] || { echo "Missing $CODE — sudo apt install ovmf" >&2; exit 1; }
  [[ -f $VM_DIR/OVMF_VARS.fd ]] || cp /usr/share/OVMF/OVMF_VARS_4M.fd "$VM_DIR/OVMF_VARS.fd"
  ARGS+=(-drive "if=pflash,format=raw,readonly=on,file=$CODE"
         -drive "if=pflash,format=raw,file=$VM_DIR/OVMF_VARS.fd")
fi

if (( DISK )); then
  [[ -f $VM_DIR/disk.qcow2 ]] || qemu-img create -q -f qcow2 "$VM_DIR/disk.qcow2" 40G
  ARGS+=(-drive "file=$VM_DIR/disk.qcow2,if=virtio,format=qcow2")
fi

if (( HEADLESS )); then
  # Kernel output only appears here if the ISO's boot entry has console=ttyS0.
  ARGS+=(-display none -serial mon:stdio)
else
  ARGS+=(-device virtio-vga -display gtk,gl=off -serial "file:$VM_DIR/serial.log")
fi

echo "ISO:  $ISO"
echo "Mode: $( ((BIOS)) && echo BIOS || echo UEFI ), ${ACCEL[1]}, ${RAM} MiB, ${CPUS} CPUs"
(( DISK )) && echo "Disk: $VM_DIR/disk.qcow2 (scratch)"
(( HEADLESS )) || echo "Serial log: $VM_DIR/serial.log   (Ctrl+Alt+G releases the mouse)"
exec qemu-system-x86_64 "${ARGS[@]}"
