#!/usr/bin/env bash
# Toggle gammastep night light. Config lives in ~/.config/gammastep/config
# (auto-location via geoclue2; falls back gracefully with a notify).
set -euo pipefail

if pgrep -x gammastep >/dev/null; then
    pkill -x gammastep
    notify-send -t 1500 "Night light" "off"
    exit 0
fi

gammastep >/dev/null 2>&1 &
sleep 1
if pgrep -x gammastep >/dev/null; then
    notify-send -t 2000 "Night light" "on — warm tint follows dusk"
else
    notify-send -u critical "Night light" "gammastep failed to start (geoclue location unavailable?)"
fi
