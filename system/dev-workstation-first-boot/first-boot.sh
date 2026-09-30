#!/usr/bin/env bash
# shellcheck disable=SC2034  # KIT_* settings are read by common/runner.sh
# =============================================================================
# SWARM_OS Suite · Dev Workstation — First Boot (secure setup on Ubuntu LTS)
# Version: 2.0.0 | Date: 2026-09-30
#
# For the build machine you use to develop BOTH operating systems:
#   SWARM_OS (LUCILLE CORE AI "LLcy")  and  I30LTZ Recovery OS (Dr. I30LTZ "MAD IT").
# This machine is neither OS. It gets coding, gaming, ISO-testing (QEMU)
# and the recovery tools as a test bench. It never writes an OS identity.
#   sudo bash first-boot.sh --dry-run --user YOURNAME
#   sudo bash first-boot.sh --user YOURNAME
# =============================================================================
KIT_ID="dev-workstation-first-boot"
KIT_TITLE="SWARM_OS Suite Dev Workstation"
KIT_VERSION="2.0.0"
KIT_DATE="2026-09-30"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEATURE_GAMING=1
NEEDS_USER=1
WRITE_OS_IDENTITY=0

kit_banner() {
  printf '%s%s' $'\033[0;36m' $'\033[1m'
  cat <<'ART'
   ██████╗ ███████╗██╗   ██╗    ██████╗ ███████╗███╗   ██╗ ██████╗██╗  ██╗
   ██╔══██╗██╔════╝██║   ██║    ██╔══██╗██╔════╝████╗  ██║██╔════╝██║  ██║
   ██║  ██║█████╗  ██║   ██║    ██████╔╝█████╗  ██╔██╗ ██║██║     ███████║
   ██║  ██║██╔══╝  ╚██╗ ██╔╝    ██╔══██╗██╔══╝  ██║╚██╗██║██║     ██╔══██║
   ██████╔╝███████╗ ╚████╔╝     ██████╔╝███████╗██║ ╚████║╚██████╗██║  ██║
   ╚═════╝ ╚══════╝  ╚═══╝      ╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝
ART
  printf '\033[0;35m   builds SWARM_OS · LLcy  \033[0;31m✚  builds I30LTZ Recovery OS · MAD IT\033[0m\n'
}

# shellcheck source=../common/runner.sh
source "$KIT_DIR/../common/runner.sh"
