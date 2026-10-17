#!/usr/bin/env bash
# DR. I30LTZ Service Watchdog
# Monitors MAD IT + SSE bridge, restarts on failure
# Version: 1.0.0  |  2026-09-25
SERVICES=(madit i30ltz-sse)
LOG="/opt/i30ltz/logs/watchdog.log"
mkdir -p "$(dirname "$LOG")"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

while true; do
  for svc in "${SERVICES[@]}"; do
    if ! systemctl is-active --quiet "$svc"; then
      echo "$(ts) [WATCHDOG] $svc dead — restarting" >> "$LOG"
      systemctl restart "$svc" 2>>"$LOG"
      /opt/i30ltz/scripts/status-notify.sh "⚠ $svc restarted" "dialog-warning" 2>/dev/null || true
    fi
  done
  sleep 30
done
