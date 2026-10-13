#!/usr/bin/env bash
# Install allsky-watchdog as a systemd user timer for the current user.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
UNITS="$HOME/.config/systemd/user"

chmod +x "$REPO/allsky-watchdog.sh"
mkdir -p "$UNITS"
sed "s|@SCRIPT@|$REPO/allsky-watchdog.sh|" "$REPO/systemd/allsky-watchdog.service.in" \
    > "$UNITS/allsky-watchdog.service"
cp "$REPO/systemd/allsky-watchdog.timer" "$UNITS/"

if [ ! -f "$HOME/.config/allsky-watchdog.conf" ]; then
    cp "$REPO/allsky-watchdog.conf.example" "$HOME/.config/allsky-watchdog.conf"
    echo "Created ~/.config/allsky-watchdog.conf (all defaults - edit to change)"
fi

systemctl --user daemon-reload
systemctl --user enable --now allsky-watchdog.timer
echo "Installed. Next run:"
systemctl --user list-timers --no-pager | grep allsky-watchdog || true
