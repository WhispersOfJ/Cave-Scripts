# Waybar config (dotfile source of truth)

Canonical copies of the desktop bar files. The live session runs from
`~/.config/waybar/` — after editing here, sync and restart the bar:

```bash
cp config      ~/.config/waybar/config
cp style.css   ~/.config/waybar/style.css
cp scripts/*.sh ~/.config/waybar/scripts/
pkill -x waybar && waybar -c ~/.config/waybar/config -s ~/.config/waybar/style.css &
```

## `custom/stack` — stack-tui launcher

`scripts/stack-tui-toggle.sh` toggles the repo's stack-tui
(`services/bash-functions/scripts/stack-tui`) in a centred floating
alacritty window on the sway scratchpad; the TUI keeps running while hidden.
A matching sway binding (`$mod+s`) fires the same script.

Subcommands:

| Command | Purpose |
|---------|---------|
| `toggle` | show / hide / launch the TUI window (waybar on-click, `$mod+s`) |
| `state` | emit waybar JSON (`open`/`closed` class + tooltip with function count and running function) |
| `opacity [value]` | set `window.opacity` live via alacritty IPC — no relaunch; applies `$STACK_TUI_OPACITY` (default 0.85) when omitted |

Env overrides: `STACK_TUI_REPO`, `STACK_TUI_TERM`, `STACK_TUI_CLASS`,
`STACK_TUI_TITLE`, `STACK_TUI_SIZE`, `STACK_TUI_OPACITY`.

The sway side needs its window rule, tracked here as
`sway/stack-tui.conf` and pulled into the session config with an `include`:

```bash
cp sway/stack-tui.conf ~/.config/sway/stack-tui.conf
swaymsg reload
```

## `custom/idle` — presentation mode

The eye module pauses/resumes the swayidle auto-lock (eye ON, aqua while
paused). swayidle runs from `~/.config/sway/swayidle.sh`; pausing stops
that process — waybar's built-in `idle_inhibitor` only talks to logind,
which swayidle ignores. The sway binding `$mod+Shift+i` fires the same
toggle as a module click.

## `custom/record` + `custom/nightlight` — state indicators

Two always-visible state dots. `custom/record` shows a muted `●` that turns
red (bold) with an elapsed `mm:ss` while `wf-recorder` runs; its state
script lives here (`scripts/record-status.sh`) and click-to-toggle calls
`~/.config/sway/recorder-toggle.sh`. `custom/nightlight` shows a dim sun
that becomes an amber moon while `gammastep` runs (click toggles via
`~/.config/sway/gammastep-toggle.sh`). The matching sway bindings are
`$mod+Shift+r` and `$mod+Shift+n`.
