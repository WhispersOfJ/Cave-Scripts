#!/usr/bin/env bash
# record-status.sh — waybar custom-module state for wf-recorder.
#
# Polled by custom/record: emits a muted "●" while nothing records and a red
# "● REC mm:ss" (class `recording`) while wf-recorder is running, with the
# elapsed time read from the recorder PID. Starting/stopping happens through
# the toggle (~/.config/hypr/scripts/recorder-toggle.sh), same split as
# custom/power → hypr/scripts/power.sh.
set -euo pipefail

pidfile="${XDG_RUNTIME_DIR:-/tmp}/wf-recorder.pid"

if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
    pid="$(cat "$pidfile")"
    secs="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [[ "$secs" =~ ^[0-9]+$ ]]; then
        printf -v elapsed '%02d:%02d' "$((10#$secs / 60))" "$((10#$secs % 60))"
    else
        elapsed="--:--"
    fi
    text="● REC $elapsed"
    class="recording"
    tooltip="Recording ($elapsed) — click to stop"
else
    text="●"
    class="idle"
    tooltip="Not recording — click to record a region"
fi

jq -nc --arg text "$text" --arg class "$class" --arg tooltip "$tooltip" \
    '{text: $text, class: $class, tooltip: $tooltip}'
