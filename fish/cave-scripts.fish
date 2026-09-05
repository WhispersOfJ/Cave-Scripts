#!/usr/bin/env fish
# ============================================================================
# cave-scripts.fish — Cave-Scripts fish loader
# ============================================================================
# Sourced from config.fish (interactive shells only). Mirrors the bash loader
# (bash/cave-scripts.sh) section-for-section with fish-native syntax:
#   1. Stack .env loader: exports the thebearcave .env at startup, honoring
#      values already set (resolved via BEARCAVE_REPO_DIR, default $HOME/cave
#      — spec §5.4).
#   2. Formatting helpers: fmt_heading, fmt_success, fmt_error, fmt_warning,
#      fmt_dim, fmt_status_dot, fmt_kv (identical output to bash/zsh).
#   3. Guarded docker compose wrapper: routes nzbdav/nzbdav_rclone recreates
#      through <BEARCAVE_REPO_DIR>/scripts/nzbdav-safe-recreate.sh (landmine
#      #3; that guard stays in thebearcave).
#   4. cave-* function library: sources every fish/functions/*.fish (the
#      stack-* alias layer ships as fish/_aliases.fish, completions as
#      fish/completions/cave-completions.fish — both generated artifacts).
# ============================================================================

# ----------------------------------------------------------------------------
# 0. Locate Cave-Scripts (this file lives at <repo>/fish/) and the thebearcave
#    checkout that owns the stack .env (spec §5.4 — path-independent).
# ----------------------------------------------------------------------------
set -l _cave_self (status filename)
set -l _cave_dir (dirname $_cave_self)
if not set -q CAVE_SCRIPTS_DIR
    set -gx CAVE_SCRIPTS_DIR (realpath $_cave_dir)
end
if not set -q BEARCAVE_REPO_DIR
    set -gx BEARCAVE_REPO_DIR $HOME/cave
end

# ----------------------------------------------------------------------------
# 1. Load the repo .env (only sets variables not already set)
# ----------------------------------------------------------------------------
function __bearcave_load_env --description 'Export $BEARCAVE_REPO_DIR/.env entries that are not already set'
    set -l env_file $BEARCAVE_REPO_DIR/.env
    test -f "$env_file"; or return 0
    while read -l line
        # Skip comments and blank lines.
        string match -q '#*' -- $line; and continue
        test -n "$line"; or continue
        set -l kv (string split -m 1 '=' -- $line)
        test (count $kv) -ge 2; or continue
        set -l key $kv[1]
        set -l value (string join '=' $kv[2..-1])
        # Strip one pair of surrounding single or double quotes.
        if string match -q '"*"' -- $value; or string match -q "'*'" -- $value
            set value (string sub -s 2 -e -1 -- $value)
        end
        test -n "$key"; or continue
        # Only set variables NOT already set (bash: [ -z "${!key+x}" ]).
        if not set -q $key
            set -gx $key $value
        end
    end < "$env_file"
end
__bearcave_load_env

# ----------------------------------------------------------------------------
# 2. Formatting helpers (respect $STACK_COLOR; byte-identical to bash/zsh)
# ----------------------------------------------------------------------------
if not set -q STACK_COLOR
    if isatty stdout
        set -gx STACK_COLOR true
    else
        set -gx STACK_COLOR false
    end
end

function _fmt_color_enabled
    test "$STACK_COLOR" = true
end

function fmt_heading
    if _fmt_color_enabled
        printf "\033[1m\033[36m%s\033[0m\n" "$argv[1]"
    else
        echo "$argv[1]"
    end
end

function fmt_success
    if _fmt_color_enabled
        printf "\033[32m%s\033[0m\n" "$argv[1]"
    else
        echo "$argv[1]"
    end
end

function fmt_error
    if _fmt_color_enabled
        printf "\033[31m%s\033[0m\n" "$argv[1]" >&2
    else
        echo "$argv[1]" >&2
    end
end

function fmt_warning
    if _fmt_color_enabled
        printf "\033[33m%s\033[0m\n" "$argv[1]"
    else
        echo "$argv[1]"
    end
end

function fmt_dim
    if _fmt_color_enabled
        printf "\033[2m%s\033[0m\n" "$argv[1]"
    else
        echo "$argv[1]"
    end
end

function fmt_status_dot
    set -l st "$argv[1]"
    if not _fmt_color_enabled
        echo "$st"
        return
    end
    set -l lc "\033[37m"
    switch (string lower -- $st)
        case running healthy up ok
            set lc "\033[32m"
        case exited down unhealthy error failed
            set lc "\033[31m"
        case warning stalled starting paused
            set lc "\033[33m"
    end
    printf "%s%s\033[0m\n" "$lc" "$st"
end

function fmt_kv
    if _fmt_color_enabled
        printf "  \033[1m%s:\033[0m %s\n" "$argv[1]" "$argv[2]"
    else
        echo "  $argv[1]: $argv[2]"
    end
end

# ----------------------------------------------------------------------------
# 2b. Stale arr-key/URL warning (same rationale as bash/zsh; tty-only)
# ----------------------------------------------------------------------------
function __bearcave_warn_stale_keys --description 'Warn when a pre-set arr key/URL differs from the .env (stale session)'
    set -l env_file $BEARCAVE_REPO_DIR/.env
    test -f "$env_file"; or return 0
    for key in RADARR_API_KEY SONARR_API_KEY PROWLARR_API_KEY RADARR_URL SONARR_URL PROWLARR_URL
        # Not pre-set: nothing to compare (set -q with a var name from data).
        if not set -q $key
            continue
        end
        set -l value $$key
        test -n "$value"; or continue
        set -l expected (string match -r "^$key=(.*)\$" -- (grep -m1 "^$key=" "$env_file" 2>/dev/null) | tail -1)
        if test -n "$expected"; and test "$value" != "$expected"
            fmt_warning "$key is set in this shell but differs from .env (stale session?) — unset it and re-source, or start a new shell"
        end
    end
end

if isatty stdout
    __bearcave_warn_stale_keys
end

# ----------------------------------------------------------------------------
# 3. Guarded docker compose wrapper (landmine #3: nzbdav non-persistent queue)
#    Mirrors the bash loader: intercepts `docker compose up|restart|start|stop|
#    rm|down ... nzbdav|nzbdav_rclone` and routes through the guard script.
#    Queries pass through; --force skips the guard (DANGEROUS).
# ----------------------------------------------------------------------------
function docker --wraps docker --description 'docker with the nzbdav queue guard'
    # Not compose, or fewer than 2 words: pass through untouched.
    if test (count $argv) -lt 2; or test "$argv[1]" != compose
        command docker $argv
        return
    end
    set -l sub $argv[2]
    switch $sub
        case up restart start stop rm down
            set -l svc_hit false
            for a in $argv
                switch $a
                    case nzbdav nzbdav_rclone
                        set svc_hit true
                end
            end
            if test "$svc_hit" != true
                command docker $argv
                return
            end
            set -l had_force false
            set -l filtered
            for a in $argv
                if test "$a" = --force
                    set had_force true
                else
                    set -a filtered $a
                end
            end
            if test "$had_force" = true
                fmt_warning "--force: skipping queue guard (queued NZBs WILL be wiped)"
                command docker $filtered
                return
            end
            set -l guard $BEARCAVE_REPO_DIR/scripts/nzbdav-safe-recreate.sh
            if test -x "$guard"
                bash "$guard" $argv[2..-1]
                return
            end
            fmt_warning "nzbdav-safe-recreate.sh not found at $guard — running unguarded"
            command docker $argv
            return
        case '*'
            command docker $argv
            return
    end
end

# ----------------------------------------------------------------------------
# 4. Interactive aliases (CachyOS fish defaults — same set as bash/zsh)
#    fish has no alias-with-args: abbreviations/functions only. ls-family
#    lives in the CachyOS config.fish already; ported here via functions so
#    the unified dotfiles install owns them (parity with .bashrc.inc).
# ----------------------------------------------------------------------------
if type -q eza
    function ls --wraps eza --description 'ls = eza -al'
        eza -al --color=always --group-directories-first --icons=always $argv
    end
    function la --wraps eza --description 'la = eza -a'
        eza -a --color=always --group-directories-first --icons=always $argv
    end
    function ll --wraps eza --description 'll = eza -l'
        eza -l --color=always --group-directories-first --icons=always $argv
    end
else
    function ls --wraps ls --description 'ls --color=auto'
        command ls --color=auto $argv
    end
    function la --wraps ls --description 'la = ls -a'
        command ls -a --color=auto $argv
    end
    function ll --wraps ls --description 'll = ls -l'
        command ls -l --color=auto $argv
    end
end

function l. --description 'list dotfiles'
    ls -a | grep -e '^\.'
end
function grep --wraps grep --description 'grep --color=auto'
    command grep --color=auto $argv
end
function fgrep --wraps fgrep --description 'fgrep --color=auto'
    command fgrep --color=auto $argv
end
function egrep --wraps egrep --description 'egrep --color=auto'
    command egrep --color=auto $argv
end
function .. --description 'cd ..'
    cd ..
end
function ... --description 'cd ../..'
    cd ../..
end
function .... --description 'cd ../../..'
    cd ../../..
end
function psmem --description 'top memory processes'
    ps auxf | sort -nr -k 4
end
function psmem10 --description 'top 10 memory processes'
    ps auxf | sort -nr -k 4 | head -10
end
function jctl --description 'journal errors for this boot'
    journalctl -p 3 -xb
end

# copy DIR1 DIR2 -> recursive copy when first arg is a directory (parity)
function copy --description 'cp -r when the first arg is a directory'
    if test (count $argv) -eq 2; and test -d "$argv[1]"
        set -l from (string trim -r -c / -- "$argv[1]")
        command cp -r "$from" "$argv[2]"
    else
        command cp $argv
    end
end

# backup FILE -> FILE.bak (parity)
function backup --description 'cp FILE FILE.bak'
    if test (count $argv) -ne 1
        echo "Usage: backup <file>" >&2
        return 1
    end
    cp "$argv[1]" "$argv[1].bak"
end

# man pages through bat (matches CachyOS fish config)
set -gx MANROFFOPT "-c"
if type -q bat
    set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
end

# ----------------------------------------------------------------------------
# 5. cave-* function library
#    Helpers first (__*.fish), then user commands (cave-*.fish), then the
#    permanent stack-* alias layer (_aliases.fish, D21), then generated
#    tab-completions. Eager sourcing keeps the surface identical to bash/zsh
#    (fish autoload would also work, but conf.d ordering makes eager simpler
#    and the offline suites assert defined-ness after sourcing the loader).
# ----------------------------------------------------------------------------
set -l _cave_repo (dirname "$CAVE_SCRIPTS_DIR")
set -l _cave_fn_dir "$CAVE_SCRIPTS_DIR/functions"
if test -d "$_cave_fn_dir"
    for _f in "$_cave_fn_dir"/__*.fish "$_cave_fn_dir"/cave-*.fish
        test -f "$_f"; and source "$_f"
    end
    set -e _f
end
set -e _cave_fn_dir

set -l _cave_aliases "$_cave_repo/fish/_aliases.fish"
test -f "$_cave_aliases"; and source "$_cave_aliases"
set -e _cave_aliases
set -e _cave_repo

set -l _cave_comp "$CAVE_SCRIPTS_DIR/completions/cave-completions.fish"
test -f "$_cave_comp"; and source "$_cave_comp"
set -e _cave_comp
