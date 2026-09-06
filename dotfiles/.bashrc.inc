# ============================================================================
# .bashrc.inc — Cave-Scripts bash wiring (sourced from ~/.bashrc)
# ============================================================================
# Managed by Cave-Scripts dotfiles/install.sh. Loaders are path-independent
# (spec §5.4): they derive CAVE_SCRIPTS_DIR from their own location.
# ============================================================================

# Load the Cave-Scripts bash port (128 cave-* commands + stack-* aliases +
# guarded docker + completions). No-op with a warning if the submodule is
# missing (fresh clones must init submodules first).
if [ -r "$HOME/cave/services/cave-scripts/bash/cave-scripts.sh" ]; then
    source "$HOME/cave/services/cave-scripts/bash/cave-scripts.sh"
else
    echo "cave-scripts: bash port not found at ~/cave/services/cave-scripts (git submodule init?)" >&2
fi

# starship prompt (bash): must run after the loader so STARSHIP_* hooks can
# override PS1 without being clobbered.
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
