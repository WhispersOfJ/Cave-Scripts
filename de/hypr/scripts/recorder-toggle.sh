#!/usr/bin/env bash
# Toggle region screen recording (wf-recorder) into ~/Videos.
# First press: slurp a region and start recording. Second press: stop and save.
set -euo pipefail

out_dir="${VIDEOS_DIR:-$HOME/Videos}"
pidfile="${XDG_RUNTIME_DIR:-/tmp}/wf-recorder.pid"

mkdir -p "$out_dir"

if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    # SIGINT makes wf-recorder finalize and save the file.
    kill -INT "$(cat "$pidfile")"
    rm -f "$pidfile"
    notify-send -t 2000 "Recording stopped" "Saved to $out_dir"
    exit 0
fi

region="$(slurp)" || exit 0
path="$out_dir/rec-$(date +%Y%m%d-%H%M%S).mp4"
wf-recorder -g "$region" -f "$path" &
echo $! > "$pidfile"
notify-send -t 2000 "Recording" "Started — press your record key again to stop" "Saving to: $path"
