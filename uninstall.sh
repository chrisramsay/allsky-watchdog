#!/usr/bin/env bash
# Remove the allsky-watchdog timer and service. Keeps config and restart log.
set -euo pipefail
systemctl --user disable --now allsky-watchdog.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/allsky-watchdog.service" \
      "$HOME/.config/systemd/user/allsky-watchdog.timer"
systemctl --user daemon-reload
echo "Removed. Config (~/.config/allsky-watchdog.conf) and history"
echo "(~/.local/state/allsky-watchdog/) were left in place."
