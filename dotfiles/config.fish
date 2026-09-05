# ============================================================================
# config.fish — Cave-Scripts fish wiring (dropped into ~/.config/fish/)
# ============================================================================
# Managed by Cave-Scripts dotfiles/install.sh. Loaders are path-independent
# (spec §5.4): they derive CAVE_SCRIPTS_DIR from their own location.
# fish had no config.fish before the M2 cutover (fresh file).
# ============================================================================

if status is-interactive
    # Load the Cave-Scripts fish port (128 cave-* commands + stack-*
    # forwarders + guarded docker wrapper + completions).
    if test -r "$HOME/cave/services/cave-scripts/fish/cave-scripts.fish"
        source "$HOME/cave/services/cave-scripts/fish/cave-scripts.fish"
    else
        echo "cave-scripts: fish port not found at ~/cave/services/cave-scripts (git submodule init?)" >&2
    end

    # starship prompt (fish): init after the loader.
    if type -q starship
        starship init fish | source
    end
end
