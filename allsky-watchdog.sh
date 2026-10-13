#!/usr/bin/env bash
# allsky-watchdog: restart indiserver + indi-allsky if no new image appears.
#
# Run every minute by allsky-watchdog.timer (systemd user timer).
# Logs to the system journal:  sudo journalctl -t allsky-watchdog
# Restart history:             ~/.local/state/allsky-watchdog/restarts.log
# Settings:                    ~/.config/allsky-watchdog.conf (optional)
set -u

# Defaults - override in the config file or the environment
IMAGE=${IMAGE:-/var/www/html/allsky/images/latest.jpg}
MAX_AGE=${MAX_AGE:-180}       # seconds without a new frame before acting
COOLDOWN=${COOLDOWN:-600}     # minimum seconds between restarts
MQTT_HOST=${MQTT_HOST:-}      # set to publish an event on each restart
MQTT_TOPIC=${MQTT_TOPIC:-allsky-watchdog/restart}
CAPTURE_UNIT=${CAPTURE_UNIT:-indi-allsky}
INDI_UNIT=${INDI_UNIT:-indiserver}

CONFIG=${CONFIG:-$HOME/.config/allsky-watchdog.conf}
# shellcheck source=/dev/null
[ -f "$CONFIG" ] && . "$CONFIG"

STATE=${XDG_STATE_HOME:-$HOME/.local/state}/allsky-watchdog
mkdir -p "$STATE"
log() { logger -t allsky-watchdog "$*"; echo "$*"; }
now=$(date +%s)

# Only act if the capture service is meant to be running (not stopped on purpose)
systemctl --user is-active --quiet "$CAPTURE_UNIT" || exit 0

# Give a freshly (re)started service time to produce its first frame
since=$(systemctl --user show -p ActiveEnterTimestamp --value "$CAPTURE_UNIT")
if [ -n "$since" ]; then
    started=$(date -d "$since" +%s 2>/dev/null || echo 0)
    (( now - started < MAX_AGE )) && exit 0
fi

[ -e "$IMAGE" ] || { log "no $IMAGE yet - skipping"; exit 0; }
age=$(( now - $(stat -L -c %Y "$IMAGE") ))     # -L: follow symlink
(( age < MAX_AGE )) && exit 0

last=$(cat "$STATE/last_restart" 2>/dev/null || echo 0)
if (( now - last < COOLDOWN )); then
    log "no new image for ${age}s, but restarted $(( now - last ))s ago - waiting"
    exit 0
fi

log "no new image for ${age}s - restarting $INDI_UNIT and $CAPTURE_UNIT"
echo "$now" > "$STATE/last_restart"
echo "$(date -Is) age=${age}s" >> "$STATE/restarts.log"

systemctl --user stop "$CAPTURE_UNIT"
systemctl --user restart "$INDI_UNIT"
sleep 5
systemctl --user start "$CAPTURE_UNIT"

if [ -n "$MQTT_HOST" ] && command -v mosquitto_pub >/dev/null; then
    mosquitto_pub -h "$MQTT_HOST" -t "$MQTT_TOPIC" -m "$age" || true
fi
