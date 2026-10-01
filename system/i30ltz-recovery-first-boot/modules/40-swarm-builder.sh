# shellcheck shell=bash
# about: SWARM_OS builder — Arch container (mkarchiso), QEMU test boots, disk-safety helper
# I30LTZ Recovery OS first boot v2.1.0 · 2026-10-01
#
# One PC: Recovery OS (this external drive) builds SWARM_OS for the internal
# NVMe. A broken SWARM_OS build can never strand you, because the builder
# lives on a different drive. Nothing here ever writes to the internal disk.

apt_install podman qemu-system-x86 qemu-utils ovmf git python3
[[ -n "$TARGET_USER" ]] && getent group kvm >/dev/null && run usermod -aG kvm "$TARGET_USER"

run install -d -o root -g i30ltz -m 2770 /var/lib/i30ltz/swarm-build \
  /var/lib/i30ltz/swarm-build/out /var/lib/i30ltz/swarm-build/work /var/lib/i30ltz/swarm-build/vm

# Helpers live in os/mkosi.extra/opt/i30ltz/bin (shared with the OS image):
#   swarm-build     archiso profile → SWARM_OS ISO, built inside an Arch container
#   swarm-test-iso  boot an ISO in a UEFI VM (real disks never attached)
#   i30ltz-disks    read-only map of which disk is which
for t in swarm-build swarm-test-iso i30ltz-disks; do install_helper "$t"; done
ok "SWARM_OS builder ready: swarm-build · swarm-test-iso · i30ltz-disks"
