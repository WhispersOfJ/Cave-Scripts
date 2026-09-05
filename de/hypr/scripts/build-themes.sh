#!/usr/bin/env bash
# build-themes.sh — bake the curated theme set under ~/.config/hypr/themes/.
#
# Each theme dir gets pre-baked files (no runtime templating):
#   colors.properties     hex palette   (used by hyprtheme for live updates)
#   waybar.css            (→ ~/.config/waybar/style.css)
#   swaync.css            (→ ~/.config/swaync/style.css)
#   wofi.css              (→ ~/.config/wofi/style.css)
#   hyprlock.conf          (→ ~/.config/hypr/hyprlock.conf)
#   alacritty-colors.toml  (→ ~/.config/alacritty/colors.toml)
#   wallpaper.png          3840x2160 gradient glow, ImageMagick
#
# The actual per-file templates live in render-theme.sh (shared with
# `hyprtheme auto`, which generates a 7th wallpaper-matched theme via
# matugen instead of picking from PALETTES below — see hyprtheme).
#
# Run after editing palettes: `bash ~/.config/hypr/scripts/build-themes.sh`
# then `hyprtheme <name>` to apply.

set -euo pipefail

THEMES="$HOME/.config/hypr/themes"
MAGICK="$(command -v magick || command -v convert)"

# shellcheck source=render-theme.sh
source "$HOME/.config/hypr/scripts/render-theme.sh"

# name|description|BG|BG_ALT|BORDER|FG|MUTED|ACCENT|RED|ORANGE|YELLOW|GREEN|BLUE|PURPLE|DIM
PALETTES=(
  "gruvbox|Gruvbox dark (current)|282828|3c3836|504945|ebdbb2|a89984|458588|fb4934|fe8019|fabd2f|8ec07c|83a598|d3869b|928374"
  "catppuccin-mocha|Catppuccin Mocha|1e1e2e|313244|45475a|cdd6f4|a6adc8|cba6f7|f38ba8|fab387|f9e2af|a6e3a1|89b4fa|cba6f7|6c7086"
  "tokyonight|Tokyo Night|1a1b26|24283b|414868|c0caf5|9aa5ce|7aa2f7|f7768e|ff9e64|e0af68|9ece6a|7aa2f7|bb9af7|565f89"
  "nord|Nord (polar night)|2e3440|3b4252|434c5e|eceff4|d8dee9|88c0d0|bf616a|d08770|ebcb8b|a3be8c|81a1c1|b48ead|616e88"
  "rose-pine|Rosé Pine|191724|1f1d2e|26233a|e0def4|908caa|ebbcba|eb6f92|f6c177|f6c177|9ccfd8|9ccfd8|c4a7e7|6e6a86"
  "dracula|Dracula|282a36|44475a|44475a|f8f8f2|6272a4|bd93f9|ff5555|ffb86c|f1fa8c|50fa7b|8be9fd|bd93f9|44475a"
)

mkdir -p "$THEMES"

for entry in "${PALETTES[@]}"; do
    IFS='|' read -r NAME DESC BG BG_ALT BORDER FG MUTED ACCENT RED ORANGE YELLOW GREEN BLUE PURPLE DIM <<< "$entry"
    D="$THEMES/$NAME"

    render_theme "$NAME" "$DESC" "$BG" "$BG_ALT" "$BORDER" "$FG" "$MUTED" "$DIM" \
                 "$ACCENT" "$RED" "$ORANGE" "$YELLOW" "$GREEN" "$BLUE" "$PURPLE"

    # ── wallpaper.png (3840x2160 gradient + glow orbs) ───────────
    case "$NAME" in
        gruvbox)          A1="$ACCENT" A2="$PURPLE" ;;
        catppuccin-mocha) A1="$ACCENT" A2="$BLUE" ;;
        tokyonight)       A1="$BLUE"   A2="$PURPLE" ;;
        nord)             A1="$ACCENT" A2="$BLUE" ;;
        rose-pine)        A1="$PURPLE" A2="$GREEN" ;;
        dracula)          A1="$PURPLE" A2="$BLUE" ;;
        *)                A1="$ACCENT" A2="$BLUE" ;;
    esac
    "$MAGICK" -size 3840x2160 gradient:"#${BG_ALT}"-"#${BG}" \
        \( -size 3840x2160 xc:none \
            -fill "#${A1}" -draw 'circle 2950,650 2950,1000' \
            -fill "#${A2}" -draw 'circle 850,1750 850,2200' \
            -fill "#${A1}" -draw 'circle 2050,320 2050,560' \) \
        -composite -blur 0x70 "$D/wallpaper.png" 2>/dev/null

    echo "built theme: $NAME"
done

echo "All themes baked into $THEMES"
