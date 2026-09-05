#!/usr/bin/env zsh
# ============================================================================
# cave-scripts.zsh — Cave-Scripts zsh loader
# ============================================================================
# Sourced from ~/.zshrc (interactive shells only). Mirrors the bash loader
# (bash/cave-scripts.sh) section-for-section with zsh-native syntax:
#   1. Stack .env loader: exports the thebearcave .env at startup, honoring
#      values already set (resolved via BEARCAVE_REPO_DIR, default $HOME/cave
#      — spec §5.4).
#   2. Formatting helpers: fmt_heading, fmt_success, fmt_error, fmt_warning,
#      fmt_dim, fmt_status_dot, fmt_kv (identical output to bash/fish).
#   3. Guarded docker compose wrapper: routes nzbdav/nzbdav_rclone recreates
#      through <BEARCAVE_REPO_DIR>/scripts/nzbdav-safe-recreate.sh (landmine
#      #3; that guard stays in thebearcave).
#   4. cave-* function library: sources every zsh/functions/*.zsh (the
#      stack-* alias layer and completions ship per-shell).
# ============================================================================

# ----------------------------------------------------------------------------
# 0. Locate Cave-Scripts (this file lives at <repo>/zsh/) and the thebearcave
#    checkout that owns the stack .env (spec §5.4 — path-independent).
# ----------------------------------------------------------------------------
_cave_self="${(%):-%x}"
_cave_self="${_cave_self:A}"                      # resolve symlinks
_cave_dir="$(cd "${_cave_self:h}" && pwd)"
CAVE_SCRIPTS_DIR="${CAVE_SCRIPTS_DIR:-$_cave_dir}"
export CAVE_SCRIPTS_DIR
BEARCAVE_REPO_DIR="${BEARCAVE_REPO_DIR:-$HOME/cave}"
export BEARCAVE_REPO_DIR

# ----------------------------------------------------------------------------
# 1. Load the repo .env (only sets variables not already set)
# ----------------------------------------------------------------------------
__bearcave_load_env() {
    local env_file="$BEARCAVE_REPO_DIR/.env"
    [ -f "$env_file" ] || return 0
    local line key value
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            \#*|"") continue ;;
        esac
        key="${line%%=*}"
        value="${line#*=}"
        case "$value" in
            \"*) value="${value#\"}"; value="${value%\"}" ;;
            \'*) value="${value#\'}"; value="${value%\'}" ;;
        esac
        if [ -n "$key" ] && [ -z "${(P)key+x}" ]; then
            export "$key=$value"
        fi
    done < "$env_file"
}
__bearcave_load_env

# ----------------------------------------------------------------------------
# 2. Formatting helpers (respect $STACK_COLOR; byte-identical to bash/fish)
# ----------------------------------------------------------------------------
if [ -z "${STACK_COLOR+x}" ]; then
    if [ -t 1 ]; then STACK_COLOR=true; else STACK_COLOR=false; fi
fi

_fmt_color_enabled() { [ "$STACK_COLOR" = true ]; }

fmt_heading() {
    if _fmt_color_enabled; then
        printf "\033[1m\033[36m%s\033[0m\n" "$1"
    else
        print -r -- "$1"
    fi
}
fmt_success() {
    if _fmt_color_enabled; then printf "\033[32m%s\033[0m\n" "$1"; else print -r -- "$1"; fi
}
fmt_error() {
    if _fmt_color_enabled; then printf "\033[31m%s\033[0m\n" "$1" >&2; else print -r -- "$1" >&2; fi
}
fmt_warning() {
    if _fmt_color_enabled; then printf "\033[33m%s\033[0m\n" "$1"; else print -r -- "$1"; fi
}
fmt_dim() {
    if _fmt_color_enabled; then printf "\033[2m%s\033[0m\n" "$1"; else print -r -- "$1"; fi
}
fmt_status_dot() {
    local st="$1"
    if ! _fmt_color_enabled; then print -r -- "$st"; return; fi
    local lc="\033[37m"
    case "${st:l}" in
        running|healthy|up|ok)              lc="\033[32m" ;;
        exited|down|unhealthy|error|failed) lc="\033[31m" ;;
        warning|stalled|starting|paused)    lc="\033[33m" ;;
    esac
    printf "%s%s\033[0m\n" "$lc" "$st"
}
fmt_kv() {
    if _fmt_color_enabled; then
        printf "  \033[1m%s:\033[0m %s\n" "$1" "$2"
    else
        print -r -- "  $1: $2"
    fi
}

# ----------------------------------------------------------------------------
# 2b. Stale arr-key/URL warning (same rationale as bash; tty-only)
# ----------------------------------------------------------------------------
__bearcave_warn_stale_keys() {
    local env_file="$BEARCAVE_REPO_DIR/.env" key value expected
    [ -f "$env_file" ] || return 0
    for key in RADARR_API_KEY SONARR_API_KEY PROWLARR_API_KEY \
               RADARR_URL SONARR_URL PROWLARR_URL; do
        [ -n "${(P)key+x}" ] || continue          # not pre-set: nothing to compare
        value="${(P)key}"
        [ -n "$value" ] || continue               # empty pre-set: loader will fill it
        expected="$(grep -E "^${key}=" "$env_file" | head -1 | cut -d= -f2- | tr -d '\"' | tr -d "'")"
        if [ -n "$expected" ] && [ "$value" != "$expected" ]; then
            fmt_warning "${key} is set in this shell but differs from .env (stale session?) — unset it and re-source, or start a new shell"
        fi
    done
}

if [ -t 1 ]; then
    __bearcave_warn_stale_keys
fi

# ----------------------------------------------------------------------------
# 3. Guarded docker compose wrapper (landmine #3: nzbdav non-persistent queue)
#    Mirrors the bash loader: intercepts `docker compose up|restart|start|stop|
#    rm|down ... nzbdav|nzbdav_rclone` and routes through the guard script.
#    Queries pass through; --force skips the guard (DANGEROUS).
# ----------------------------------------------------------------------------
docker() {
    if [ "$#" -lt 2 ] || [ "$1" != compose ]; then
        command docker "$@"; return $?
    fi
    local sub="$2"
    case "$sub" in
        up|restart|start|stop|rm|down)
            local _svc_hit=false _a
            for _a in "$@"; do
                case "$_a" in nzbdav|nzbdav_rclone) _svc_hit=true ;; esac
            done
            if [ "$_svc_hit" != true ]; then
                command docker "$@"; return $?
            fi
            local _a2 _args=() _had_force=false
            for _a2 in "$@"; do
                if [ "$_a2" = --force ]; then _had_force=true; else _args+=("$_a2"); fi
            done
            if [ "$_had_force" = true ]; then
                fmt_warning "--force: skipping queue guard (queued NZBs WILL be wiped)"
                command docker "${_args[@]}"
                return $?
            fi
            local guard="$BEARCAVE_REPO_DIR/scripts/nzbdav-safe-recreate.sh"
            if [ -x "$guard" ]; then
                shift   # drop leading `docker`
                bash "$guard" "$@"
                return $?
            fi
            fmt_warning "nzbdav-safe-recreate.sh not found at $guard — running unguarded"
            command docker "$@"
            return $?
            ;;
        *)
            command docker "$@"; return $?
            ;;
    esac
}

# ----------------------------------------------------------------------------
# 4. Interactive aliases (CachyOS fish defaults — same set as the bash loader)
# ----------------------------------------------------------------------------
if command -v eza >/dev/null 2>&1; then
    alias ls='eza -al --color=always --group-directories-first --icons=always'
    alias la='eza -a --color=always --group-directories-first --icons=always'
    alias ll='eza -l --color=always --group-directories-first --icons=always'
else
    alias ls='ls --color=auto'
    alias la='ls -a --color=auto'
    alias ll='ls -l --color=auto'
fi
alias l.='ls -a | grep -e "^\\."'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias jctl='journalctl -p 3 -xb'

# copy DIR1 DIR2 -> recursive copy when first arg is a directory (fish parity)
copy() {
    if [ "$#" -eq 2 ] && [ -d "$1" ]; then
        local from="${1%/}"
        command cp -r "$from" "$2"
    else
        command cp "$@"
    fi
}

# backup FILE -> FILE.bak (fish parity)
backup() {
    [ "$#" -eq 1 ] || { print -u2 "Usage: backup <file>"; return 1; }
    cp "$1" "$1.bak"
}

# man pages through bat (matches CachyOS fish config)
export MANROFFOPT="-c"
if command -v bat >/dev/null 2>&1; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# ----------------------------------------------------------------------------
# 5. cave-* function library
#    Helpers first (__*.zsh), then user commands (cave-*.zsh). The permanent
#    stack-* alias layer (D21) and the completions are shared generated
#    artifacts: the alias file is pure POSIX function syntax (identical in
#    every shell — one copy in the bash tree, generated from
#    spec/functions.yaml), and the metadata parser behind cave-help is the
#    bash tree's __metadata.sh. Both are referenced repo-relatively, exactly
#    like the __metadata.zsh shim does.
# ----------------------------------------------------------------------------
_cave_repo="${CAVE_SCRIPTS_DIR:h}"                   # <repo>
_cave_fn_dir="$CAVE_SCRIPTS_DIR/functions"
if [ -d "$_cave_fn_dir" ]; then
    for _f in "$_cave_fn_dir"/__*.zsh "$_cave_fn_dir"/cave-*.zsh; do
        [ -f "$_f" ] && source "$_f"
    done
    unset _f
fi
unset _cave_fn_dir

_cave_aliases="$_cave_repo/bash/_aliases.sh"
[ -f "$_cave_aliases" ] && source "$_cave_aliases"
unset _cave_aliases

# compdef-based completions (native zsh — bash's `complete -F` file is not
# reusable; zsh compdefs are generated into completions/_cave-* from the
# shared metadata). Register the compdef file so the `complete:` specs on
# each cave-* function drive TAB completion in zsh.
_cave_compdef="$CAVE_SCRIPTS_DIR/completions/_cave-cmd"
if [ -f "$_cave_compdef" ]; then
    fpath=("$CAVE_SCRIPTS_DIR/completions" $fpath)
    autoload -Uz compinit
    compinit -u
fi
unset _cave_compdef _cave_repo
