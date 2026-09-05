#!/usr/bin/env bash
# weather.sh — waybar custom-module: current conditions for a fixed ZIP code
# via wttr.in (no API key/signup needed). Cached on disk with a TTL so
# waybar's 2s-class poll interval doesn't hit the network every cycle —
# only one real fetch every $TTL seconds, everything else reads the cache.
set -euo pipefail

ZIP="${WEATHER_ZIP:-14613}"
TTL="${WEATHER_TTL:-1800}" # 30 min — conditions don't change fast enough to poll harder
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-weather"
RAW="$CACHE_DIR/raw"

mkdir -p "$CACHE_DIR"

fresh() {
    [ -s "$RAW" ] && [ "$(( $(date +%s) - $(stat -c %Y "$RAW") ))" -lt "$TTL" ]
}

fetch() {
    curl -fsS --max-time 5 "https://wttr.in/${ZIP}?format=%C|%t|%f|%h|%w|%S|%s" 2>/dev/null
}

if ! fresh; then
    if data="$(fetch)"; then
        printf '%s\n' "$data" > "$RAW"
    fi
fi

if [ ! -s "$RAW" ]; then
    jq -nc '{text: "󰼯 --°", tooltip: "Weather unavailable (network or wttr.in down)", class: "offline"}'
    exit 0
fi

IFS='|' read -r cond temp_raw feels_raw humidity wind sunrise sunset < "$RAW"
# temp_raw/feels_raw arrive like "+67°F" — strip the sign and unit down to the bare number.
temp="${temp_raw#[+-]}"
temp="${temp%%°*}"
feels="${feels_raw#[+-]}"
feels="${feels%%°*}"
# sunrise/sunset arrive as HH:MM:SS — trim to HH:MM.
sunrise="${sunrise%:*}"
sunset="${sunset%:*}"

# Map condition text to a Material Design (nf-md) glyph — same icon family
# already used elsewhere in this bar (e.g. the GPU module's 󰢮), so it stays
# visually consistent rather than mixing in wttr.in's colored emoji.
lc="$(printf '%s' "$cond" | tr '[:upper:]' '[:lower:]')"
case "$lc" in
    *thunder*|*storm*)              icon="󰖓" ;;
    *snow*|*sleet*|*blizzard*|*ice*) icon="󰼶" ;;
    *drizzle*|*shower*)             icon="󰼳" ;;
    *rain*)                         icon="󰖗" ;;
    *fog*|*mist*|*haze*)            icon="󰖑" ;;
    *overcast*)                     icon="󰖐" ;;
    *cloud*)                        icon="󰖕" ;;
    *clear*|*sunny*)                icon="󰖙" ;;
    *)                               icon="󰼯" ;;
esac

jq -nc --arg text "$icon ${temp}°" \
       --arg tooltip "$cond, ${temp}°F (feels $feels°)
Humidity: $humidity · Wind: $wind
Sunrise $sunrise · Sunset $sunset
ZIP $ZIP · click to refresh" \
    '{text: $text, tooltip: $tooltip, class: "ok"}'
