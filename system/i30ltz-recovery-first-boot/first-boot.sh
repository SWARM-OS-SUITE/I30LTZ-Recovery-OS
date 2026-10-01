#!/usr/bin/env bash
# shellcheck disable=SC2034  # KIT_* settings are read by common/runner.sh
# =============================================================================
# I30LTZ Recovery OS — First Boot (secure setup, Ubuntu LTS base, external USB drive)
# Version: 2.1.0 | Date: 2026-10-01
# Assistant: Dr. I30LTZ "MAD IT" — PC repair + data recovery + SWARM_OS builder
#
# Run on the fresh Recovery OS install on the external drive. Never on
# SWARM_OS (the X13's internal NVMe).
#   sudo bash first-boot.sh --dry-run --user "$USER"
#   sudo bash first-boot.sh --user "$USER"
# =============================================================================
KIT_ID="i30ltz-first-boot"
KIT_TITLE="I30LTZ Recovery OS"
KIT_VERSION="2.1.0"
KIT_DATE="2026-10-01"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEATURE_GAMING=0
NEEDS_USER=0

kit_banner() {
  printf '%s%s' $'\033[0;31m' $'\033[1m'
  cat <<'ART'
   ██╗██████╗  ██████╗ ██╗  ████████╗███████╗
   ██║╚════██╗██╔═████╗██║  ╚══██╔══╝╚══███╔╝
   ██║ █████╔╝██║██╔██║██║     ██║     ███╔╝
   ██║ ╚═══██╗████╔╝██║██║     ██║    ███╔╝
   ██║██████╔╝╚██████╔╝███████╗██║   ███████╗
   ╚═╝╚═════╝  ╚═════╝ ╚══════╝╚═╝   ╚══════╝
ART
  printf '\033[0;33m   RECOVERY OS · Dr. I30LTZ "MAD IT" · builds SWARM_OS\033[0m\n'
}

# shellcheck source=../common/runner.sh
source "$KIT_DIR/../common/runner.sh"
