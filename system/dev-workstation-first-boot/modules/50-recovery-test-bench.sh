# shellcheck shell=bash
# about: MAD IT recovery tools as a test bench (no I30LTZ OS identity)
# SWARM_OS Suite dev workstation v2.0.0 · 2026-09-30
# Reuses the I30LTZ Recovery OS module so both machines test the same tools.

WRITE_OS_IDENTITY=0
# shellcheck source=../../i30ltz-recovery-first-boot/modules/50-recovery-mad-it.sh
source "$KIT_DIR/../i30ltz-recovery-first-boot/modules/50-recovery-mad-it.sh"
