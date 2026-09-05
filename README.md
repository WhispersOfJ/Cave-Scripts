# Cave-Scripts

The Bear Cave's shell-operational surface — every command that runs this
media stack, the desktop, and the host — implemented as **three parallel,
hand-maintained ports: bash, zsh, and fish** with identical behaviour,
output, and safety guarantees.

> Status: **initial scaffold (M1)**. The library is being migrated out of
> `WhispersOfJ/thebearcave` per the plan in that repo's
> `cave-scripts-spec.md` / `cave-scripts-plan.md` / `cave-scripts-inventory.md`.

## Layout

```
bash/          # port 1: bash   (loader, functions/, completions/, scripts/)
zsh/           # port 2: zsh    (loader, functions/, completions/, scripts/)
fish/          # port 3: fish   (loader, functions/, completions/, scripts/)
de/            # desktop assets + runtime scripts (waybar, hypr, themes) + sync
dotfiles/      # unified shell dotfiles (.bashrc.inc, .zshrc.inc, config.fish, starship.toml)
spec/          # functions.yaml — the canonical registry driving every port
tests/         # per-shell offline suites (merge gate)
```

## Naming

- **`cave-*`** — every function (e.g. `cave-arr-backlog`).
- **`cave-sys-*`** — host/system diagnostics (e.g. `cave-sys-pkg-update`).
- **`stack-*`** — kept permanently as deprecated aliases.

## Install

Not yet available — per-shell loaders and the installer ship in milestone M2.
Until then the operational surface remains at thebearcave
(`services/bash-functions/`).

## License

MIT — see [LICENSE](LICENSE).
