#!/usr/bin/env bash
# shellcheck disable=SC2034  # KIT_* settings are read by common/runner.sh
# =============================================================================
# I30LTZ Recovery OS — First Boot (secure setup, Ubuntu LTS base, runs from an external drive)
# Version: 2.0.0 | Date: 2026-09-30
# Assistant: Dr. I30LTZ "MAD IT" — PC repair + data recovery
#
# For the machine that IS I30LTZ Recovery OS. Not for SWARM_OS, and not for
# the dev workstation (use ../dev-workstation-first-boot there).
#   sudo bash first-boot.sh --dry-run
#   sudo bash first-boot.sh
# =============================================================================
KIT_ID="i30ltz-first-boot"
KIT_TITLE="I30LTZ Recovery OS"
KIT_VERSION="2.0.0"
KIT_DATE="2026-09-30"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEATURE_GAMING=0
NEEDS_USER=0
WRITE_OS_IDENTITY=1

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
  printf '\033[0;33m   RECOVERY OS · Dr. I30LTZ "MAD IT"\033[0m\n'
}

# shellcheck source=../common/runner.sh
source "$KIT_DIR/../common/runner.sh"
