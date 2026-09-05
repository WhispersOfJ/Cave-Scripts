#!/usr/bin/env bash
# stack-tui-toggle.sh — waybar custom-module backend for the repo's stack-tui.
#
# Click   → toggle the stack-tui TUI (services/bash-functions/scripts/stack-tui)
#           in a centred floating window: launch → float → resize → center.
#           A second click tucks it into Hyprland's `special:scratchpad`
#           workspace (hidden on every monitor, not just the current one);
#           the TUI process keeps running, so re-opening is instant and the
#           output pane keeps its history. q/esc inside the TUI quits the
#           terminal window entirely.
#           Window tracking is done via `hyprctl clients -j` matched on
#           class, not sway's `swaymsg`/scratchpad-container model — see
#           HYPR.md section 6 for why this needed rewriting after the
#           sway→Hyprland migration.
# State   → prints waybar JSON {text,class,tooltip} so style.css drives the
#           look via #custom-stack (state by opacity, not extra colours).
#           Tooltip shows the stack-function count and what is running.
# Opacity → `opacity <value>` applies window.opacity live to the running TUI
#           window via alacritty's IPC socket (no relaunch). Without an
#           argument it applies $OPACITY; a value + `--persist` also rewrites
#           the OPACITY default in this script.
#
# Env overrides:
#   STACK_TUI_TERM      terminal emulator   (default: alacritty)
#   STACK_TUI_REPO      repo root           (default: ~/cave)
#   STACK_TUI_CLASS     Wayland app_id      (default: stack_tui)
#   STACK_TUI_TITLE     window title        (default: stack-tui)
#   STACK_TUI_SIZE      WxH in px           (default: 1400x900)
#   STACK_TUI_OPACITY   window opacity      (default: 0.85)

set -euo pipefail

REPO="${STACK_TUI_REPO:-$HOME/cave}"
TERM_BIN="${STACK_TUI_TERM:-alacritty}"
APP_CLASS="${STACK_TUI_CLASS:-stack_tui}"
APP_TITLE="${STACK_TUI_TITLE:-stack-tui}"
SIZE="${STACK_TUI_SIZE:-1400x900}"
OPACITY="${STACK_TUI_OPACITY:-0.85}"

TUI="$REPO/services/bash-functions/scripts/stack-tui"
GLYPH="󰆍"
SEL="class:^(${APP_CLASS})\$" # hyprctl window selector for our terminal

emit() { # emit <class> <tooltip>  — jq builds the JSON, no escaping pitfalls
    jq -nc --arg text "$GLYPH" --arg class "$1" --arg tooltip "$2" \
        '{text: $text, class: $class, tooltip: $tooltip}'
}

# All mapped windows matching our class, as a JSON array (one hyprctl call,
# reused by total_count/hidden_count so a single toggle/state run doesn't
# shell out to hyprctl twice).
stack_windows_json() {
    hyprctl -j clients | jq --arg cls "$APP_CLASS" '[.[] | select(.class == $cls)]'
}

# Total number of stack_tui windows anywhere.
total_count() {
    stack_windows_json | jq 'length'
}

# Number of stack_tui windows currently parked in special:scratchpad (hidden
# on every monitor regardless of whether that special workspace is toggled
# visible — see toggle()/launch() below).
hidden_count() {
    stack_windows_json | jq '[.[] | select(.workspace.name == "special:scratchpad")] | length'
}

window_open()    { [ "$(total_count)" -gt 0 ]; }
window_visible() { [ "$(total_count)" -gt 0 ] && [ "$(hidden_count)" -eq 0 ]; }

# Find the alacritty PID driving the stack_tui window (so we can read the
# ALACRITTY_WINDOW_ID its children export for IPC scoping).
alacritty_pid() {
    pgrep -f "alacritty --class $APP_CLASS" 2>/dev/null | head -1 || true
}

# Apply window.opacity live via alacritty IPC, scoped to the TUI window only.
apply_opacity() {
    local value="$1" pid wid
    pid="$(alacritty_pid)"
    [ -n "$pid" ] || { echo "stack-tui window not running" >&2; return 1; }
    # alacritty exports ALACRITTY_WINDOW_ID into its child (the TUI) env;
    # read it from there to scope the IPC call to this window only.
    # /proc/*/environ is NUL-separated — tr before matching.
    wid="$(for c in $(pgrep -P "$pid" 2>/dev/null); do
            tr '\0' '\n' <"/proc/$c/environ" 2>/dev/null \
                | sed -n 's/^ALACRITTY_WINDOW_ID=//p'
        done | head -1)"
    [ -n "$wid" ] || { echo "ALACRITTY_WINDOW_ID not found (pid $pid)" >&2; return 1; }
    "$TERM_BIN" msg config -w "$wid" "window.opacity=$value" >/dev/null
}

cmd_opacity() {
    local value="${1:-$OPACITY}"
    if apply_opacity "$value"; then
        echo "opacity set to $value"
    else
        echo "opacity failed" >&2
        return 1
    fi
}

launch() {
    [ -x "$TUI" ] || { notify-send -u critical "stack-tui" \
        "launcher not found: $TUI" 2>/dev/null || true; exit 1; }
    # Serialize launches: the alacritty window takes ~1s to map, so two
    # rapid toggles can both see "no window" here and spawn duplicates
    # (found by hammering the module in testing). Non-blocking: a concurrent
    # launcher already running is treated as this toggle's launch.
    exec 9>"${XDG_CACHE_HOME:-$HOME/.cache}/waybar-stack-tui/launch.lock"
    if ! flock -n 9; then
        # Another toggle is mid-launch; give its window a beat to map and
        # treat this toggle as a show/no-op rather than a second launch.
        sleep 1
        return 0
    fi
    local log="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-stack-tui/tui.log"
    mkdir -p "$(dirname "$log")"
    # alacritty: --class sets the Wayland app_id, --title the window title;
    # slight transparency keeps the floating panel visually light. TUI output
    # goes to a log so post-mortems are possible when the window vanishes.
    "$TERM_BIN" --class "$APP_CLASS" --title "$APP_TITLE" \
        -o "window.opacity=$OPACITY" \
        -e "$TUI" >>"$log" 2>&1 &
    disown
    # Give the window a beat to map before floating/sizing/centering it.
    local mapped=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if window_open; then mapped=1; break; fi
        sleep 0.15
    done
    if [ "$mapped" -eq 0 ]; then
        # Never mapped: the terminal died on startup. Leave a breadcrumb in
        # the log path instead of leaving a phantom "launching" state.
        notify-send -u critical "stack-tui" \
            "terminal failed to map — see $log" 2>/dev/null || true
        return 1
    fi
    # Float it, focus it, size it, then centre the (now-focused) window.
    # hyprland.conf also floats class stack_tui via windowrule, but set it
    # explicitly here too so this script doesn't silently depend on that
    # rule existing elsewhere.
    local w h
    w="${SIZE%x*}"; h="${SIZE#*x}"
    hyprctl --batch "dispatch setfloating $SEL ; dispatch focuswindow $SEL ; \
        dispatch resizewindowpixel exact $w $h,$SEL ; dispatch centerwindow" >/dev/null 2>&1 || true
}

toggle() {
    if window_visible; then
        # Visible → tuck it into special:scratchpad (hidden on every
        # monitor; movetoworkspacesilent doesn't switch the active workspace).
        hyprctl dispatch movetoworkspacesilent "special:scratchpad,$SEL" >/dev/null 2>&1 || true
    elif window_open; then
        # Hidden → bring it back to whatever workspace is active now, and
        # focus it (it doesn't grab focus on its own after the move).
        local cur_ws
        cur_ws="$(hyprctl -j activeworkspace | jq -r '.id')"
        hyprctl --batch "dispatch movetoworkspacesilent $cur_ws,$SEL ; dispatch focuswindow $SEL" >/dev/null 2>&1 || true
    else
        launch
    fi
}

# --- tooltip body -----------------------------------------------------------
# Functions: one cached call to stack-tui --list (the metadata parse costs
# ~1s), memoised on disk with a 60s TTL so the 2s state poll stays cheap.
FUNCS_TTL=60
FUNC_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-stack-tui/func-count"
function_count() {
    if [ -f "$FUNC_CACHE" ] && [ "$(( $(date +%s) - $(stat -c %Y "$FUNC_CACHE") ))" -lt "$FUNCS_TTL" ]; then
        cat "$FUNC_CACHE"
        return
    fi
    local n
    n="$("$TUI" --list 2>/dev/null | wc -l)"
    mkdir -p "$(dirname "$FUNC_CACHE")"
    printf '%s' "$n" > "$FUNC_CACHE"
    printf '%s' "$n"
}

# Detect the TUI actually running a stack function right now (uv → python →
# bash/timeout chains all name the function in their cmdline).
running_line() {
    local match
    match="$(pgrep -af 'bash -c .*source.*bearcave-bash\.sh|timeout [0-9]+ bash -c' 2>/dev/null | \
        grep -v grep | head -1 || true)"
    [ -z "$match" ] && return 1
    # First cmdline token starting with "stack-" is the fired function name.
    local fn
    fn="$(printf '%s' "$match" | awk '{for(i=1;i<=NF;i++) if($i ~ /^stack-/){print $i; exit}}')"
    [ -n "$fn" ] || return 1
    printf 'running: %s' "$fn"
}

tooltip_body() {
    local count running
    count="$(function_count 2>/dev/null || echo '?')"
    running="$(running_line || true)"
    printf '%s stack functions' "$count"
    [ -n "$running" ] && printf '\n%s' "$running"
    return 0
}

case "${1:-toggle}" in
    toggle)
        toggle
        ;;
    state)
        local_tip="$(tooltip_body)"
        if window_visible; then
            emit "open" "stack-tui open — ${local_tip//$'\n'/ · } — click to hide"
        elif window_open; then
            emit "closed" "stack-tui hidden — ${local_tip//$'\n'/ · } — click to show"
        else
            emit "closed" "stack-tui — ${local_tip//$'\n'/ · } — click to launch"
        fi
        ;;
    opacity)
        shift
        cmd_opacity "${1:-}"
        ;;
    *)
        echo "usage: $0 {toggle|state|opacity [value]}" >&2
        exit 2
        ;;
esac
