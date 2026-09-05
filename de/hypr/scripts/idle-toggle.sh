#!/usr/bin/env bash
# idle-toggle.sh — pause/resume hypridle ("presentation mode").
#
# hypridle drives the auto-lock (5 min) and output power-off (10 min) from
# ~/.config/hypr/hypridle.conf. Same toggle/state interface as the sway
# version, so waybar's custom/idle module keeps working unchanged.
#
# Subcommands:
#   toggle    pause (kill) or resume (relaunch) hypridle, with a notify
#   state     waybar JSON: eye ON (class on) while auto-lock is paused
set -euo pipefail

IDLE_BIN="${IDLE_BIN:-hypridle}"
GLYPH_ON=""
GLYPH_OFF=""

running() { pgrep -x hypridle >/dev/null 2>&1; }

emit() {
    jq -nc --arg text "$1" --arg class "$2" --arg tooltip "$3" \
        '{text: $text, class: $class, tooltip: $tooltip}'
}

do_toggle() {
    if running; then
        pkill -x hypridle
        notify-send -t 2000 "Idle lock" "paused — screen will not lock"
    else
        "$IDLE_BIN" >/dev/null 2>&1 &
        disown
        sleep 1
        if running; then
            notify-send -t 2000 "Idle lock" "resumed — locks after 5 min idle"
        else
            notify-send -u critical "Idle lock" "hypridle failed to start — check ~/.config/hypr/hypridle.conf"
        fi
    fi
}

case "${1:-toggle}" in
    toggle)
        do_toggle
        ;;
    state)
        if running; then
            emit "$GLYPH_OFF" "off" "Auto-lock on (5 min idle) — click to pause"
        else
            emit "$GLYPH_ON" "on" "Idle lock paused — screen stays awake — click to resume"
        fi
        ;;
    *)
        echo "usage: $0 {toggle|state}" >&2
        exit 2
        ;;
esac