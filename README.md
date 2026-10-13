# allsky-watchdog

A small systemd watchdog for [indi-allsky](https://github.com/aaronwmorris/indi-allsky):
if the camera stops producing images, it restarts `indiserver` and `indi-allsky`
so you don't lose a night of frames.

## Why

With some cameras (here a ZWO ASI676MC on a Raspberry Pi 5) the driver
occasionally fails to fetch a frame:

```
[ERROR] Failed to get data after exposure (3552x3552 #1 channels) (ASI_ERROR_TIMEOUT).
```

The exposure then stays in the **BUSY** state indefinitely. indi-allsky's own
`CCD_EXPOSURE_TIMEOUT` doesn't always recover it, so capture stops until someone
notices. Restarting the INDI server and indi-allsky clears it.

## How it works

A systemd **user** timer runs `allsky-watchdog.sh` every minute. The script:

1. does nothing if `indi-allsky` is stopped on purpose
2. does nothing for the first `MAX_AGE` seconds after `indi-allsky` (re)starts,
   so a fresh boot isn't mistaken for a hang
3. checks the age of the newest image (`latest.jpg`, following symlinks)
4. if no new frame has appeared for `MAX_AGE` seconds (default 180), stops
   `indi-allsky`, restarts `indiserver`, waits 5 s and starts `indi-allsky`
5. won't restart again within `COOLDOWN` seconds (default 600), so a camera
   that's truly wedged doesn't cause a restart loop
6. logs every restart to the journal and a history file, and can publish an
   MQTT event

Recovery typically takes about a minute (reconnect plus first exposure).

## Requirements

- indi-allsky installed with its standard **user** services (`indi-allsky`,
  `indiserver`) — check with `systemctl --user list-units | grep -i indi`
- user lingering enabled, as indi-allsky's installer sets up
  (`loginctl show-user $USER -p Linger` → `Linger=yes`)
- optional: `mosquitto-clients` for MQTT events

## Install

As the user that runs indi-allsky (usually `pi`):

```bash
git clone https://github.com/<you>/allsky-watchdog.git ~/allsky-watchdog
cd ~/allsky-watchdog
bash install.sh
```

`install.sh` makes the script executable, writes the service unit pointing at
wherever you cloned the repo, installs the timer, creates
`~/.config/allsky-watchdog.conf` from the example (if it doesn't exist), and
enables the timer.

## Check it's working

```bash
systemctl --user list-timers | grep allsky-watchdog     # last/next run
systemctl --user status allsky-watchdog.service --no-pager
```

A healthy run shows `inactive (dead)` with `status=0/SUCCESS` — it's a one-shot
job that exits quietly when frames are fresh. A failed run shows `failed`.

### Test it

Force one restart regardless of image age:

```bash
MAX_AGE=1 COOLDOWN=0 ~/allsky-watchdog/allsky-watchdog.sh
sudo journalctl -t allsky-watchdog
```

Frames should resume within about a minute. Remember to ignore this entry when
counting real hangs later.

## Logs and history

```bash
sudo journalctl -t allsky-watchdog                      # every decision it logged
cat ~/.local/state/allsky-watchdog/restarts.log         # one line per restart
sudo journalctl --since "3 days ago" | grep -c ASI_ERROR_TIMEOUT   # driver timeouts
```

Comparing restarts against driver timeouts shows how often indi-allsky recovers
on its own versus needing the watchdog.

Raspberry Pi OS may keep the journal in memory only, losing history on reboot.
Make it persistent:

```bash
sudo mkdir -p /var/log/journal
sudo systemctl restart systemd-journald
```

## Settings

Edit `~/.config/allsky-watchdog.conf` (shell syntax, `NAME=value`). Changes
apply on the next run — no reload needed.

| Setting | Default | Meaning |
|---|---|---|
| `IMAGE` | `/var/www/html/allsky/images/latest.jpg` | File whose age is checked |
| `MAX_AGE` | `180` | Seconds without a new frame before restarting |
| `COOLDOWN` | `600` | Minimum seconds between restarts |
| `CAPTURE_UNIT` | `indi-allsky` | Capture service (user unit) |
| `INDI_UNIT` | `indiserver` | INDI server service (user unit) |
| `MQTT_HOST` | *(empty)* | Broker to publish restart events to; empty disables |
| `MQTT_TOPIC` | `allsky-watchdog/restart` | Topic; the message is the frame age in seconds |

`MAX_AGE` must stay well above your longest capture cycle (maximum exposure +
download + processing + period). 180 s suits cycles up to about a minute.

## Uninstall

```bash
bash ~/allsky-watchdog/uninstall.sh
```

Removes the timer and service; leaves your config and restart history.

## Files

```
allsky-watchdog/
├── allsky-watchdog.sh              the watchdog
├── allsky-watchdog.conf.example    settings template
├── install.sh / uninstall.sh
└── systemd/
    ├── allsky-watchdog.service.in  template (path filled in by install.sh)
    └── allsky-watchdog.timer       every minute, starting 5 min after boot
```
