#!/usr/bin/env bash
# Clipboard history picker: cliphist list -> wofi -> copy selection back.
set -euo pipefail

entry="$(cliphist list | wofi --dmenu -p 'Clipboard' -i -k /dev/null)" || exit 0
if [[ -n "$entry" ]]; then
    printf '%s' "$entry" | cliphist decode | wl-copy
fi
