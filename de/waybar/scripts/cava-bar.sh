#!/usr/bin/env bash
# cava-bar.sh — waybar custom-module: live mini audio spectrum.
# Streaming module (no "interval" set in waybar/config) — this process stays
# alive under waybar and one JSON line is emitted per cava frame, rather than
# being re-invoked on a poll interval like the other custom modules.
set -uo pipefail # no -e: one malformed frame line shouldn't kill the stream

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/cava/waybar.conf"
BARS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

cava -p "$CONF" 2>/dev/null | while IFS=';' read -ra vals; do
    out=""
    for v in "${vals[@]}"; do
        [[ "$v" =~ ^[0-9]+$ ]] || continue
        idx=$v
        [ "$idx" -gt 7 ] && idx=7
        out+="${BARS[$idx]}"
    done
    [ -z "$out" ] && out="▁▁▁▁▁▁▁▁"
    jq -nc --arg text "$out" '{text: $text, tooltip: "live spectrum (click to open cava fullscreen)", class: "on"}'
done
