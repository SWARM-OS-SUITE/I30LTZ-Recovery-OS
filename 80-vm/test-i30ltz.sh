#!/usr/bin/env bash
# I30LTZ Recovery OS — QEMU Test Launcher
# Version: 0.2.0-alpha | Date: 2026-10-05
# Run: bash /mnt/recoverybuild/80-vm/test-i30ltz.sh [path/to/iso]
# -------------------------------------------------------

set -e

RELEASES="/mnt/recoverybuild/10-releases"
VM_DIR="/mnt/recoverybuild/80-vm"
DISK="$VM_DIR/test.qcow2"
DISK_SIZE="20G"
MEM="4096"
CPUS="2"

# Find latest ISO if not specified
ISO="${1:-$(ls -t "$RELEASES"/*.iso 2>/dev/null | head -1)}"

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
  echo "[VM] ERROR: No ISO found. Run build.sh first or pass ISO path as arg."
  echo "     Usage: $0 [path/to/i30ltz-recovery.iso]"
  exit 1
fi

echo "[VM] I30LTZ Recovery OS — QEMU Test"
echo "[VM] ISO:  $ISO"
echo "[VM] RAM:  ${MEM}MB | CPUs: $CPUS"
echo ""

# Create test disk if not exists
if [ ! -f "$DISK" ]; then
  echo "[VM] Creating ${DISK_SIZE} test disk at $DISK ..."
  qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
fi

# Check for KVM
KVM_ARGS=""
if [ -r /dev/kvm ]; then
  KVM_ARGS="-enable-kvm -cpu host"
  echo "[VM] KVM enabled (faster)"
else
  echo "[VM] WARNING: KVM not available — emulation will be slow"
fi

# Launch
exec qemu-system-x86_64 \
  $KVM_ARGS \
  -m "$MEM" \
  -smp "$CPUS" \
  -cdrom "$ISO" \
  -drive "file=$DISK,format=qcow2,if=virtio" \
  -net nic,model=virtio \
  -net user,hostfwd=tcp::5555-:5000 \
  -vga virtio \
  -display sdl \
  -boot d \
  -name "I30LTZ Recovery OS v0.2.0-alpha"

# Note: port 5555 on host → port 5000 (boltz) in VM
# Test boltz from host:
#   curl -s -X POST http://localhost:5555/boltz \
#     -H "X-Swarm-Auth: <token from: i30ltz pair  (run inside the VM)>" \
#     -H "Content-Type: application/json" \
#     -d '{"message":"system status"}'
