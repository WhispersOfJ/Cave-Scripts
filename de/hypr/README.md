# Hyprland setup — quick reference

Session: pick **Hyprland** at the ly login screen (sway stays available).

## Theme switching
```
hyprtheme              # wofi picker (also: $mod+Shift+T)
hyprtheme <name>       # gruvbox | catppuccin-mocha | tokyonight | nord | rose-pine | dracula
hyprtheme list
```
Applies border colors (live), waybar/swaync/wofi CSS, hyprlock colors and
wallpaper. Editable palettes live in `~/.config/hypr/scripts/build-themes.sh`
(re-run it, then `hyprtheme <name>`).

## Keybindings ($mod = Super)
| Keys | Action |
|---|---|
| $mod+Return / $mod+d | terminal (foot) / launcher (wofi) |
| $mod+Shift+q / Shift+c | kill window / reload config |
| $mod+Shift+e / $mod+Escape | power menu (wlogout) / lock (hyprlock) |
| $mod+hjkl / arrows | focus |
| $mod+Shift+hjkl | move window |
| $mod+1..0 / Shift | switch / move-to workspace |
| $mod+b / v / e | toggle split (dwindle) |
| $mod+w / s | tab group (sway tabbed/stacking equivalent) |
| $mod+f / Shift+Space / Space | fullscreen / float toggle / cycle focus |
| $mod+Shift+minus / $mod+minus | scratchpad: move / show |
| $mod+r | resize mode (hjkl/arrows, Esc to exit) |
| $mod+Shift+s | hyprshot region |
| $mod+Shift+p | hyprpicker (copies hex) |
| $mod+Shift+r / v / n / i | record region / cliphist / night light / idle toggle |
| $mod+Shift+t | theme switcher |
| Print / $mod+Print / $mod+Shift+Print | full / region / region→swappy screenshot |

## Layout & polish
Gaps inner 12 / outer 6 · 2px borders · 10px rounding · soft blur + shadows ·
animations. Idle: lock 5 min, DPMS off 10 min (`hypridle`, toggled by
`idle-toggle.sh`).

## Notes
- Media/brightness keys → swayosd OSD (unchanged).
- Waybar custom modules (stack-tui, idle, record, nightlight) still run from
  `~/.config/waybar/scripts/` and `~/.config/sway/` scripts.
- `hyprlock.conf` is regenerated per theme — edit the theme template in
  `build-themes.sh` if you want a different look.