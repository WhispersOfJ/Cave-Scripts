# ============================================================================
# .zshrc.inc — Cave-Scripts zsh wiring (sourced from ~/.zshrc)
# ============================================================================
# Managed by Cave-Scripts dotfiles/install.sh. Loaders are path-independent
# (spec §5.4): they derive CAVE_SCRIPTS_DIR from their own location.
#
# p10k cutover note (plan M2 task 7): install.sh comments out the
# Powerlevel10k instant-prompt block and the `source ~/.p10k.zsh` line in
# ~/.zshrc before sourcing this file — starship replaces p10k as the prompt.
# The CachyOS zsh config source (`cachyos-config.zsh`) STAYS: it provides
# keybindings/history that starship does not.
# ============================================================================

# Load the Cave-Scripts zsh port (128 cave-* commands + stack-* aliases +
# guarded docker + compdef completions). No-op with a warning if the
# submodule is missing (fresh clones must init submodules first).
if [[ -r "$HOME/cave/services/cave-scripts/zsh/cave-scripts.zsh" ]]; then
    source "$HOME/cave/services/cave-scripts/zsh/cave-scripts.zsh"
else
    print -u2 "cave-scripts: zsh port not found at ~/cave/services/cave-scripts (git submodule init?)"
fi

# starship prompt (zsh): initialized after the loader. The p10k instant
# prompt must already be disabled by install.sh — two prompt systems racing
# for precmd hooks produce flicker and doubled right-prompts.
if (( $+commands[starship] )); then
    eval "$(starship init zsh)"
fi
