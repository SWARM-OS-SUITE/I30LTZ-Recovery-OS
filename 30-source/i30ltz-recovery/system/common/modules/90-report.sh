# shellcheck shell=bash
# about: writes a dated report of what this machine now looks like
# Ubuntu first-boot shared module v2.0.0 · 2026-09-30

[[ "$DRY_RUN" == 1 ]] && { info "dry run — no report written"; return 0; }
report="$LOG_DIR/report_${RUN_ID}.md"
{
  echo "# ${KIT_TITLE} first-boot report"
  echo "kit v${KIT_VERSION} (${KIT_DATE}) · run ${RUN_ID} · user ${TARGET_USER:-none}"
  echo
  echo "- OS: $(. /etc/os-release; echo "$PRETTY_NAME") · kernel $(uname -r)"
  echo "- GPU: ${GPU_VENDOR:-unknown} · $(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -1 | cut -d: -f3- | xargs)"
  echo "- Firewall: $(ufw status 2>/dev/null | head -1)"
  echo "- AppArmor: $(aa-enabled 2>/dev/null || echo unknown)"
  echo "- SSH: $(systemctl is-active ssh 2>/dev/null || echo inactive)"
  echo "- Auto security updates: $(systemctl is-enabled unattended-upgrades 2>/dev/null)"
  echo "- Warnings: ${#WARNINGS[@]}"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
} >"$report"
chmod 0640 "$report"
ok "report: $report"
