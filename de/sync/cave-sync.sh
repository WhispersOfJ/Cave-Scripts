#!/usr/bin/env bash
# cave-sync — push the versioned DE assets (this repo's de/) to the live
# ~/.config session and reload what needs reloading.
#
#   cave-sync.sh waybar          # config, style.css, scripts/ -> ~/.config/waybar
#   cave-sync.sh hypr            # confs, scripts/, themes/    -> ~/.config/hypr
#   cave-sync.sh all             # both, then reload
#   cave-sync.sh <target> --check # report drift (cmp) without writing
#
# M1 skeleton: bash only. Per-shell cave-sync functions (cave-sync, D14) ship
# with the three-shell library in M3. The live dirs are sync TARGETS only —
# edit assets here, never under ~/.config.
set -euo pipefail

DE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${HOME}"
CHECK=0
TARGET=""

for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        waybar|hypr|all) TARGET="$arg" ;;
        *) echo "usage: cave-sync.sh [--check] <waybar|hypr|all>" >&2; exit 2 ;;
    esac
done
[ -n "$TARGET" ] || { echo "usage: cave-sync.sh [--check] <waybar|hypr|all>" >&2; exit 2; }

dirty=0

sync_one() { # src dst
    local src="$1" dst="$2"
    if [ "$CHECK" -eq 1 ]; then
        if cmp -s "$src" "$dst"; then
            echo "  ok   ${src#"$DE"/}"
        else
            echo "  drift ${src#"$DE"/}"
            dirty=1
        fi
    else
        cp -p "$src" "$dst"
        echo "  synced ${src#"$DE"/}"
    fi
}

sync_dir_files() { # src_dir dst_dir (copies regular files, not subdirs)
    local src_dir="$1" dst_dir="$2"
    mkdir -p "$dst_dir"
    for f in "$src_dir"/*; do
        [ -f "$f" ] && sync_one "$f" "$dst_dir/$(basename "$f")"
    done
}

want_hypr=0; want_waybar=0
[ "$TARGET" = all ] || [ "$TARGET" = waybar ] && want_waybar=1
[ "$TARGET" = all ] || [ "$TARGET" = hypr ] && want_hypr=1

if [ "$want_waybar" -eq 1 ]; then
    echo "waybar:"
    sync_one "$DE/waybar/config"      "$HOME_DIR/.config/waybar/config"
    sync_one "$DE/waybar/style.css"   "$HOME_DIR/.config/waybar/style.css"
    sync_dir_files "$DE/waybar/scripts" "$HOME_DIR/.config/waybar/scripts"
fi

if [ "$want_hypr" -eq 1 ]; then
    echo "hypr:"
    for f in hyprland.conf hyprlock.conf hypridle.conf hyprpaper.conf; do
        sync_one "$DE/hypr/$f" "$HOME_DIR/.config/hypr/$f"
    done
    sync_dir_files "$DE/hypr/scripts" "$HOME_DIR/.config/hypr/scripts"
    # Theme dirs are whole trees.
    mkdir -p "$HOME_DIR/.config/hypr/themes"
    for d in "$DE/hypr/themes"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        if [ "$CHECK" -eq 1 ]; then
            if diff -qr "$d" "$HOME_DIR/.config/hypr/themes/$name" >/dev/null 2>&1; then
                echo "  ok   hypr/themes/$name"
            else
                echo "  drift hypr/themes/$name"; dirty=1
            fi
        else
            rm -rf "$HOME_DIR/.config/hypr/themes/$name"
            cp -r "$d" "$HOME_DIR/.config/hypr/themes/$name"
            echo "  synced hypr/themes/$name"
        fi
    done
fi

if [ "$CHECK" -eq 1 ]; then
    [ "$dirty" -eq 0 ] && echo "OK: de/ assets match the live copies." || echo "DRIFT: see lines above."
    exit "$dirty"
fi

# Reload the affected surfaces (never in --check).
# Restart waybar THROUGH Hyprland (hyprctl dispatch exec) rather than
# backgrounding it from here: a plain `nohup waybar &` is reaped when the
# invoking shell exits (non-interactive runs), leaving the bar dead. hyprctl
# spawns it the same way the session's `exec-once = waybar` does, so it
# survives regardless of caller.
if [ "$want_waybar" -eq 1 ]; then
    pkill -x waybar 2>/dev/null || true
    if command -v hyprctl >/dev/null 2>&1 && hyprctl activeworkspace >/dev/null 2>&1; then
        hyprctl dispatch exec waybar >/dev/null 2>&1 || true
    else
        setsid waybar >/dev/null 2>&1 < /dev/null &
    fi
    echo "waybar restarted"
fi
if [ "$want_hypr" -eq 1 ]; then
    hyprctl reload >/dev/null 2>&1 || true
    echo "hyprctl reload sent"
fi
echo "cave-sync done"
