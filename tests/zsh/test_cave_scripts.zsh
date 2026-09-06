#!/usr/bin/env zsh
# ============================================================================
# Cave-Scripts — Zsh Offline Smoke Test
# ============================================================================
# Verifies the zsh port (zsh/) against the canonical registry
# (spec/functions.yaml) and against the bash port (bash/) itself:
# every registered command exists as a cave-* function, every stack-* alias
# forwarder exists and maps to the right cave-* target, all zsh files parse
# (zsh -n), the compdef completions are current and register both spellings,
# and — the Demo-2 crown check — the zsh port produces byte-identical output
# to the bash port for the same command (cave-help, cave-version, and the
# mocked renderer units run under BOTH shells and diffed).
#
# Tiers:
#   syntax:        every zsh/ file parses (zsh -n; generators stay bash)
#   load/define:   the zsh loader defines the full cave-* surface (128)
#   registry:      every functions.yaml row with a zsh impl exists (cave-*)
#   aliases:       the shared _aliases.sh loads under zsh; every stack-*
#                  forwarder targets the right cave-* (same mapping as bash)
#   helpers:       __helpers + fmt_* + guarded docker() present under zsh
#   completions:   _cave-cmd parses (zsh -n), registers cave-* + stack-*,
#                  compdef file current (gen-zsh-completions.sh --check)
#   parity:        byte-identical output vs the bash port for cave-version,
#                  cave-help, and the mocked renderer fixtures
#   unit:          mocked renderer tests (missing-aired sonarr/radarr,
#                  requests, unwatched) with the zsh loader
#   guard:         arg-requiring commands refuse cleanly with no args
#
# The live read-only tier stays in thebearcave (D11/D13 split) — this suite
# is the merge gate and is CI-safe with zero network/stack access.
#
# Usage:
#   zsh tests/zsh/test_cave_scripts.zsh
# ============================================================================
set -euo pipefail

# Isolate from the real HOME: sourcing the loader runs compinit -u, which
# writes ~/.zcompdump — redirect it to a throwaway dir so the test never
# touches (or poisons) the user's real completion cache.
TEST_HOME="$(mktemp -d)"
export HOME="$TEST_HOME"
export ZDOTDIR="$TEST_HOME"
trap 'rm -rf "$TEST_HOME"' EXIT

RED=$'\e[0;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[1;33m'
BLUE=$'\e[0;34m'
NC=$'\e[0m'

log_info()    { print -r -- "${BLUE}[INFO]${NC} $1"; }
log_success() { print -r -- "${GREEN}[PASS]${NC} $1"; }
log_warning() { print -r -- "${YELLOW}[WARN]${NC} $1"; }
log_error()   { print -r -- "${RED}[FAIL]${NC} $1"; }

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ZSH_DIR="$REPO_DIR/zsh"
FUNC_DIR="$ZSH_DIR/functions"
BASH_DIR="$REPO_DIR/bash"
BASH_FUNC_DIR="$BASH_DIR/functions"
REGISTRY="$REPO_DIR/spec/functions.yaml"

# The loader defaults BEARCAVE_REPO_DIR to $HOME/cave; with HOME redirected
# to an isolated temp dir that path does not exist. Point it at this repo so
# repo-relative commands (cave-version's git log line, the stale-key probe)
# resolve identically in every subprocess — and stay CI-safe (no dependency
# on a real /home/bear/cave checkout).
export BEARCAVE_REPO_DIR="$REPO_DIR"

cd "$REPO_DIR"

passed=0
failed=0

# Source the zsh loader once so cave-* functions, stack-* aliases, fmt_*
# helpers, and the guarded docker() wrapper are defined for the checks.
# shellcheck disable=SC2034
STACK_COLOR=false
# shellcheck disable=SC1091
source "$ZSH_DIR/cave-scripts.zsh" >/dev/null 2>&1

assert_defined() {
    local name="$1" label="$2"
    if (( $+functions[$name] )); then
        passed=$((passed + 1))
        log_success "defines: $label"
    else
        failed=$((failed + 1))
        log_error "defines: $label (function missing)"
    fi
}

print ""
print "=========================================="
print "  Cave-Scripts Zsh Offline Smoke Test"
print "=========================================="
print ""

# --- Syntax tier: every zsh file parses ---
log_info "Syntax checks (zsh -n on every zsh/ file)..."
load_fail=0
setopt null_glob   # no-match globs expand to nothing (completion file has no .zsh suffix)
for f in "$FUNC_DIR"/*.zsh "$ZSH_DIR"/cave-scripts.zsh \
         "$ZSH_DIR"/completions/_cave-* "$ZSH_DIR"/functions/__*.zsh; do
    [ -f "$f" ] || continue
    if ! zsh -n "$f" 2>/dev/null; then
        load_fail=$((load_fail + 1))
        log_error "syntax: ${f#$REPO_DIR/}"
    fi
done
unsetopt null_glob
# The generators are bash scripts (they drive sed/printf over the shared
# parser) — syntax-check them with bash, exactly as the bash suite does.
for f in "$ZSH_DIR"/scripts/gen-*.sh; do
    [ -f "$f" ] || continue
    if ! bash -n "$f" 2>/dev/null; then
        load_fail=$((load_fail + 1))
        log_error "syntax (generator): ${f#$REPO_DIR/}"
    fi
done
if [ "$load_fail" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "all zsh/ files parse (zsh -n) + generators parse (bash -n)"
else
    failed=$((failed + load_fail))
fi

# --- Load/define: cave-* commands found in function files ---
CAVE_CMDS=("${(@f)$(
    for f in "$FUNC_DIR"/cave-*.zsh; do
        grep -oE '^cave-[a-z0-9-]+\(\)' "$f" 2>/dev/null | sed 's/()$//'
    done | sort -u
)}")
# Legacy-alias surface = commands whose registry family has a stack-* source
# (media/core/sys). Families born as cave-* (de/backup/btrfs) have no legacy
# alias and are excluded from count assertions against the alias file.
LEGACY_CMDS=("${(@f)$(
    for cmd in "${CAVE_CMDS[@]}"; do
        family="$(python3 -c "
import yaml
reg = yaml.safe_load(open('$REGISTRY'))
for f in reg['functions']:
    if f['name'] == '$cmd':
        print(f['family'])
        break
")"
        case "$family" in
            de|backup|btrfs) ;;
            *) print "$cmd" ;;
        esac
    done
)}")
if [ "${#CAVE_CMDS[@]}" -eq 0 ]; then
    failed=$((failed + 1))
    log_error "no cave-* commands found in $FUNC_DIR"
else
    passed=$((passed + 1))
    log_success "${#CAVE_CMDS[@]} cave-* commands defined across function files"
fi

# --- Load/define: every cave-* source file defines a function in-shell ---
log_info "Load check (sourced functions are callable)..."
undef=0
for cmd in "${CAVE_CMDS[@]}"; do
    if ! (( $+functions[$cmd] )); then
        undef=$((undef + 1))
        log_error "source-defined function missing in shell: $cmd"
    fi
done
if [ "$undef" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "every cave-* command is callable after sourcing the loader"
else
    failed=$((failed + undef))
fi

# --- Registry conformance: every row with a zsh impl exists as cave-* ---
# Rows without an implementation yet (de/backup, built later in M3) are
# skipped; btrfs landed in M3 and is now enforced like the media families.
log_info "Registry conformance (spec/functions.yaml rows → cave-* functions)..."
reg_missing=0
reg_rows=("${(@f)$(python3 - "$REGISTRY" <<'PY'
import sys, yaml
reg = yaml.safe_load(open(sys.argv[1]))
for f in reg['functions']:
    if f['family'] not in ('de', 'backup'):
        print(f['name'])
PY
)}")
for cave_name in "${reg_rows[@]}"; do
    [ -n "$cave_name" ] || continue
    if ! (( $+functions[$cave_name] )); then
        reg_missing=$((reg_missing + 1))
        log_error "registry row missing from zsh port: $cave_name"
    fi
done
if [ "$reg_missing" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "every registry row (non-M3 families) has a cave-* function"
else
    failed=$((failed + reg_missing))
fi

# --- Registry conformance: every cave-* def has a registry row (no orphans) ---
log_info "Registry conformance (cave-* defs → registry rows, no orphans)..."
orphans=0
reg_lookup() {
    python3 - "$REGISTRY" "$1" <<'PY' | grep -q .
import sys, yaml
reg = yaml.safe_load(open(sys.argv[1]))
for f in reg['functions']:
    if f['name'] == sys.argv[2]:
        print(f['name'])
        break
PY
}
for cave_name in "${CAVE_CMDS[@]}"; do
    [ -n "$cave_name" ] || continue
    if ! reg_lookup "$cave_name"; then
        orphans=$((orphans + 1))
        log_error "cave-* function has no registry row: $cave_name"
    fi
done
if [ "$orphans" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "every cave-* def has a registry row (no orphans)"
else
    failed=$((failed + orphans))
fi

# --- Alias tier: shared _aliases.sh loads under zsh and matches bash ---
log_info "Alias conformance (shared _aliases.sh: stack-* → cave-* mapping)..."
# The alias file is pure POSIX function syntax generated once (D21); both
# ports source the SAME file, so the definitive mapping lives in the bash
# tree. Assert: the file loads in zsh, every alias targets an existing
# cave-* function, and the alias set exactly matches the bash-suite surface
# (same count of stack-* forwarders in both ports).
ALIAS_FILE="$BASH_DIR/_aliases.sh"
if [ ! -f "$ALIAS_FILE" ]; then
    failed=$((failed + 1))
    log_error "shared alias file missing: $ALIAS_FILE"
else
    alias_bad=0
    ALIASES=("${(@f)$(grep -oE '^stack-[a-z0-9-]+\(\)' "$ALIAS_FILE" | sed 's/()$//' | sort -u)}")
    if [ "${#ALIASES[@]}" -ne "${#LEGACY_CMDS[@]}" ]; then
        alias_bad=$((alias_bad + 1))
        log_error "alias count (${#ALIASES[@]}) != legacy cave-* count (${#LEGACY_CMDS[@]})"
    fi
    for alias_name in "${ALIASES[@]}"; do
        [ -n "$alias_name" ] || continue
        # Alias line:  stack-<name>() { cave-<target> "$@"; }
        target="$(grep -E "^${alias_name}\(\) \\{ " "$ALIAS_FILE" \
            | sed -E "s/^${alias_name}\(\) \\{ (cave-[a-z0-9-]+) .*/\\1/")"
        if [ -z "$target" ]; then
            alias_bad=$((alias_bad + 1))
            log_error "alias missing forwarder or target: $alias_name"
            continue
        fi
        if ! (( $+functions[$alias_name] )); then
            alias_bad=$((alias_bad + 1))
            log_error "alias not defined in zsh: $alias_name"
            continue
        fi
        if ! (( $+functions[$target] )); then
            alias_bad=$((alias_bad + 1))
            log_error "alias $alias_name targets missing function $target"
        fi
    done
    if [ "$alias_bad" -eq 0 ]; then
        passed=$((passed + 1))
        log_success "${#ALIASES[@]} stack-* aliases defined in zsh, all targets resolve"
    else
        failed=$((failed + alias_bad))
    fi
fi

# --- Alias functional check: stack-X invocation == cave-X invocation ---
log_info "Alias functional check (stack-version ≡ cave-version in zsh)..."
ver_cave="$(STACK_COLOR=false cave-version 2>&1)" && vrc=0 || vrc=$?
ver_stack="$(STACK_COLOR=false stack-version 2>&1)" && src=0 || src=$?
if [ "$vrc" -eq "$src" ] && [ "$ver_cave" = "$ver_stack" ] && [ -n "$ver_cave" ]; then
    passed=$((passed + 1))
    log_success "stack-version output identical to cave-version in zsh"
else
    failed=$((failed + 1))
    log_error "alias mismatch (cave rc=$vrc [$ver_cave] vs stack rc=$src [$ver_stack])"
fi

# --- Helpers: fmt_*, __helpers, guarded docker() under zsh ---
for h in fmt_heading fmt_success fmt_error fmt_warning fmt_dim fmt_status_dot fmt_kv \
         __arr_api __arr_api_url __arr_api_key __stack_arr_app \
         __plex_api __plex_butler __seerr_api __nzbdav_api __stack_containers \
         __stack_curl __bearcave_load_env __bearcave_warn_stale_keys; do
    assert_defined "$h" "$h"
done

if (( $+functions[docker] )); then
    passed=$((passed + 1))
    log_success "guarded docker() wrapper is defined under zsh"
else
    failed=$((failed + 1))
    log_error "guarded docker() wrapper is missing (loader did not define it)"
fi

# --- Completions: compdef parses, registers both spellings, no drift ---
log_info "Completion checks (generated compdef parses, registers, is current)..."
COMP_FILE="$ZSH_DIR/completions/_cave-cmd"
if [ ! -f "$COMP_FILE" ]; then
    failed=$((failed + 1))
    log_error "compdef file missing: $COMP_FILE"
else
    if zsh -n "$COMP_FILE" 2>/dev/null; then
        passed=$((passed + 1))
        log_success "compdef file parses (zsh -n)"
    else
        failed=$((failed + 1))
        log_error "compdef file fails to parse"
    fi
    # Both spellings in the #compdef registration line: cave-* AND stack-*.
    reg_cave="$(grep -E '^#compdef ' "$COMP_FILE" | grep -oE '\bcave-[a-z0-9-]+' | sort -u | wc -l | tr -d ' ')"
    reg_stack="$(grep -E '^#compdef ' "$COMP_FILE" | grep -oE '\bstack-[a-z0-9-]+' | sort -u | wc -l | tr -d ' ')"
    if [ "$reg_cave" -ge 128 ] && [ "$reg_stack" -ge 128 ]; then
        passed=$((passed + 1))
        log_success "compdef registers $reg_cave cave-* + $reg_stack stack-* spellings"
    else
        failed=$((failed + 1))
        log_error "compdef registration incomplete (cave=$reg_cave stack=$reg_stack)"
    fi
fi

log_info "completion drift check (gen-zsh-completions.sh --check)..."
if bash "$ZSH_DIR/scripts/gen-zsh-completions.sh" --check >/dev/null 2>&1; then
    passed=$((passed + 1))
    log_success "zsh completions are current (no drift)"
else
    failed=$((failed + 1))
    log_error "zsh completions are out of date — run gen-zsh-completions.sh"
fi

# --- Parity tier: bash and zsh ports are byte-identical on shared commands ---
# The Demo-2 contract: the same command run in bash and zsh produces the same
# bytes. Every parity pair sources its own loader and diffs stdout/stderr.
log_info "parity: cave-version + cave-help byte-identical to the bash port..."
run_both() {
    local script="$1"
    local bash_out zsh_out bash_rc zsh_rc
    bash_out="$(bash -c "
        unset CAVE_SCRIPTS_DIR   # parent zsh loader exported it; let bash self-locate
        STACK_COLOR=false
        source '$BASH_DIR/cave-scripts.sh' >/dev/null 2>&1
        $script
    " 2>&1)" && bash_rc=0 || bash_rc=$?
    zsh_out="$(zsh -f -c "
        unset CAVE_SCRIPTS_DIR   # parent loader exported it; self-locate fresh
        STACK_COLOR=false
        source '$ZSH_DIR/cave-scripts.zsh' >/dev/null 2>&1
        $script
    " 2>&1)" && zsh_rc=0 || zsh_rc=$?
    if [ "$bash_rc" -eq "$zsh_rc" ] && [ "$bash_out" = "$zsh_out" ]; then
        passed=$((passed + 1))
        log_success "parity: $script (rc=$bash_rc, byte-identical)"
    else
        failed=$((failed + 1))
        log_error "parity: $script diverges (bash rc=$bash_rc vs zsh rc=$zsh_rc)"
        diff <(print -r -- "$bash_out") <(print -r -- "$zsh_out") \
            | head -6 | sed 's/^/         /'
    fi
}
run_both "cave-version"
run_both "cave-help"

# --- Parity: cave-arr-missing-aired sonarr renderer (mock, both shells) ---
log_info "parity: missing-aired sonarr renderer (mock fixture, bash vs zsh)..."
mock_file="$(mktemp)"
trap 'rm -f "$mock_file"; rm -rf "$TEST_HOME"' EXIT
printf '%s' '{"records":[{"seriesId":42,"seasonNumber":3,"episodeNumber":7,"title":"The Test"},{"seriesId":7,"seasonNumber":1,"episodeNumber":2,"title":"Second"}],"totalRecords":3}' > "$mock_file"
bash_out="$(SONARR_URL='http://127.0.0.1:1' SONARR_API_KEY='mock-key' STACK_COLOR=false bash -c '
    MOCK_FILE="$2"
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __stack_curl() { cat "$MOCK_FILE"; }
    "$3" sonarr 5
' _ "$BASH_DIR/cave-scripts.sh" "$mock_file" cave-arr-missing-aired 2>&1)" && brc=0 || brc=$?
zsh_out="$(SONARR_URL='http://127.0.0.1:1' SONARR_API_KEY='mock-key' STACK_COLOR=false zsh -f -c '
    MOCK_FILE="$2"
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __stack_curl() { cat "$MOCK_FILE"; }
    "$3" sonarr 5
' _ "$ZSH_DIR/cave-scripts.zsh" "$mock_file" cave-arr-missing-aired 2>&1)" && zrc=0 || zrc=$?
rm -f "$mock_file"
if [ "$brc" -eq "$zrc" ] && [ "$bash_out" = "$zsh_out" ] \
    && printf '%s' "$bash_out" | grep -q '? S03E07 The Test' \
    && printf '%s' "$bash_out" | grep -q '? S01E02 Second' \
    && printf '%s' "$bash_out" | grep -q '... and 1 more'; then
    passed=$((passed + 1))
    log_success "parity: missing-aired sonarr renderer byte-identical + correct (rc=$brc)"
else
    failed=$((failed + 1))
    log_error "parity: missing-aired sonarr renderer diverges (bash rc=$brc vs zsh rc=$zrc)"
    printf '%s\n' "--- zsh output ---"
    print -r -- "$zsh_out" | tail -6 | sed 's/^/         /'
fi

# --- Parity: cave-requests Seerr renderer (mock, both shells) ---
log_info "parity: cave-requests Seerr renderer (mock fixture, bash vs zsh)..."
seerr_counts_mock="$(mktemp)"
seerr_list_mock="$(mktemp)"
printf '%s' '{"total":10,"movie":6,"tv":4,"pending":0,"approved":2,"declined":1,"failed":0,"processing":1,"available":0,"completed":6}' > "$seerr_counts_mock"
printf '%s' '{"pageInfo":{"pages":1,"pageSize":10,"results":6,"page":1},"results":['\
'{"id":1,"status":2,"type":"movie","media":{"title":null,"tmdbId":41264,"status":3},"requestedBy":{"plexUsername":"RequesterA"}},'\
'{"id":2,"status":2,"type":"movie","media":{"title":"Watchable Now","tmdbId":77,"status":5},"requestedBy":{"plexUsername":"RequesterD"}},'\
'{"id":3,"status":1,"type":"tv","media":{"title":null,"tvdbId":55,"status":2},"requestedBy":{"plexUsername":"RequesterF"}},'\
'{"id":4,"status":5,"type":"movie","media":{"title":"Closed And Available","tmdbId":99,"status":5},"requestedBy":{"plexUsername":"RequesterB"}},'\
'{"id":5,"status":3,"type":"movie","media":{"title":"Declined Flick","tmdbId":123,"status":3},"requestedBy":{"plexUsername":"RequesterE"}},'\
'{"id":6,"status":4,"type":"tv","media":{"title":"Failed Show","tmdbId":456,"status":3},"requestedBy":{"plexUsername":"RequesterG"}}]}' > "$seerr_list_mock"
bash_out="$(SEERR_API_KEY='mock-key' STACK_COLOR=false bash -c '
    COUNTS="$2" LIST="$3"
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __seerr_api() {
        case "$2" in
            *"request/count"*) cat "$COUNTS" ;;
            *) cat "$LIST" ;;
        esac
    }
    "$4" 10
' _ "$BASH_DIR/cave-scripts.sh" "$seerr_counts_mock" "$seerr_list_mock" cave-requests 2>&1)" && brc=0 || brc=$?
zsh_out="$(SEERR_API_KEY='mock-key' STACK_COLOR=false zsh -f -c '
    COUNTS="$2" LIST="$3"
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __seerr_api() {
        case "$2" in
            *"request/count"*) cat "$COUNTS" ;;
            *) cat "$LIST" ;;
        esac
    }
    "$4" 10
' _ "$ZSH_DIR/cave-scripts.zsh" "$seerr_counts_mock" "$seerr_list_mock" cave-requests 2>&1)" && zrc=0 || zrc=$?
rm -f "$seerr_counts_mock" "$seerr_list_mock"
if [ "$brc" -eq "$zrc" ] && [ "$bash_out" = "$zsh_out" ] \
    && printf '%s' "$bash_out" | grep -q 'total=10 pending=0 approved=2 declined=1 failed=0' \
    && printf '%s' "$bash_out" | grep -q '\[movie\] tmdb:41264 - by RequesterA (processing)' \
    && ! printf '%s' "$bash_out" | grep -q 'Closed And Available'; then
    passed=$((passed + 1))
    log_success "parity: requests renderer byte-identical + correct (rc=$brc)"
else
    failed=$((failed + 1))
    log_error "parity: requests renderer diverges (bash rc=$brc vs zsh rc=$zrc)"
    printf '%s\n' "--- zsh output ---"
    print -r -- "$zsh_out" | tail -6 | sed 's/^/         /'
fi

# --- Unit: cave-arrival-notify --help prints usage (zsh, offline) ---
log_info "unit: cave-arrival-notify --help prints usage (zsh)..."
arr_help_out="$(zsh -f -c '
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    "$2" --help
' _ "$ZSH_DIR/cave-scripts.zsh" cave-arrival-notify 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && print -r -- "$arr_help_out" | grep -q 'Usage: cave-arrival-notify'; then
    passed=$((passed + 1))
    log_success "unit: arrival-notify --help prints usage (exit 0)"
else
    failed=$((failed + 1))
    log_error "unit: arrival-notify --help unexpected (rc=$rc): [$arr_help_out]"
fi

# --- Unit: cave-activity-feed refuses >1 arg (zsh, offline) ---
log_info "unit: cave-activity-feed refuses extra args (zsh)..."
feed_usage_out="$(zsh -f -c '
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    "$2" 5 bogus
' _ "$ZSH_DIR/cave-scripts.zsh" cave-activity-feed 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 1 ] && print -r -- "$feed_usage_out" | grep -q 'Usage: cave-activity-feed'; then
    passed=$((passed + 1))
    log_success "unit: activity-feed refuses >1 arg with usage (exit 1)"
else
    failed=$((failed + 1))
    log_error "unit: activity-feed usage unexpected (rc=$rc): [$feed_usage_out]"
fi

# --- Unit: stale arr key/URL warning (zsh, offline) ---
log_info "unit: stale arr key warning fires on mismatch, silent on match (zsh)..."
stale_tmp="$(mktemp -d)"
printf 'SONARR_API_KEY=real-key\nRADARR_URL=http://real:7878\n' > "$stale_tmp/.env"
stale_out="$(SONARR_API_KEY='stale-key' RADARR_URL='http://real:7878' \
    BEARCAVE_REPO_DIR="$stale_tmp" STACK_COLOR=false zsh -f -c '
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' _ "$ZSH_DIR/cave-scripts.zsh" 2>&1)" && rc=0 || rc=$?
match_out="$(SONARR_API_KEY='real-key' RADARR_URL='http://real:7878' \
    BEARCAVE_REPO_DIR="$stale_tmp" STACK_COLOR=false zsh -f -c '
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' _ "$ZSH_DIR/cave-scripts.zsh" 2>&1)" && rc=0 || rc=$?
noenv_out="$(SONARR_API_KEY='stale-key' BEARCAVE_REPO_DIR="$(mktemp -d)" \
    STACK_COLOR=false zsh -f -c '
    # shellcheck disable=SC1091
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' _ "$ZSH_DIR/cave-scripts.zsh" 2>&1)" && rc=0 || rc=$?
rm -rf "$stale_tmp"
if print -r -- "$stale_out" | grep -q 'SONARR_API_KEY' \
    && ! print -r -- "$stale_out" | grep -q 'RADARR_URL' \
    && [ -z "$match_out" ] && [ -z "$noenv_out" ]; then
    passed=$((passed + 1))
    log_success "unit: stale arr key warning fires on mismatch, silent on match (zsh)"
else
    failed=$((failed + 1))
    log_error "unit: stale arr key warning unexpected (stale=[$stale_out] match=[$match_out] noenv=[$noenv_out])"
fi

# --- Guard tier: mutating/arg-requiring commands refuse cleanly with no args ---
log_info "Guard tier (no-args invocations must print usage and exit cleanly)..."
run_guard() {
    local name="$1"
    local output rc
    output="$(timeout 20 zsh -f -c "
        STACK_COLOR=false
        source '$ZSH_DIR/cave-scripts.zsh' >/dev/null 2>&1
        $name
    " </dev/null 2>&1)" && rc=0 || rc=$?
    if [ "$rc" -le 1 ] && [ -n "$output" ]; then
        passed=$((passed + 1))
        log_success "guard: $name (exit $rc, refused with output)"
    else
        failed=$((failed + 1))
        log_error "guard: $name (exit $rc, $([ -n "$output" ] && print 'had output' || print 'no output'))"
        print -r -- "$output" | tail -3 | sed 's/^/         /'
    fi
}

for cmd in \
    cave-arr-backlog cave-arr-blocklist cave-arr-clear-blocklist \
    cave-arr-import cave-arr-import-candidates cave-arr-logs \
    cave-arr-missing-aired cave-arr-queue-errors cave-arr-recently-added \
    cave-arr-toggle-search cave-container cave-cutoff-unmet cave-disk-reclaim \
    cave-import-lists cave-loop-candidates cave-loop-exclude cave-loop-unmonitor \
    cave-radarr-prune cave-sonarr-prune cave-worktree \
    cave-btrfs-snapshot cave-btrfs-subvol cave-btrfs-scrub \
    cave-btrfs-balance cave-btrfs-snapper; do
    if (( ${CAVE_CMDS[(I)$cmd]} )); then
        run_guard "$cmd"
    fi
done

# cave-restart-all prompts for confirmation; with no stdin it must decline.
if (( ${CAVE_CMDS[(I)cave-restart-all]} )); then
    run_guard cave-restart-all
fi

# --- Btrfs tier (M3): dry-run echo-before-exec, /boot refusal, closed-stdin abort ---
log_info "Btrfs tier (dry-run echo-before-exec, /boot refusal, closed-stdin abort)..."
run_btrfs_rc() { # dry-run variant: sets BTRFS_OUT + BTRFS_RC
    BTRFS_OUT="$(timeout 20 zsh -f -c "
        STACK_COLOR=false
        CAVE_BTRFS_DRYRUN=1
        source '$ZSH_DIR/cave-scripts.zsh' >/dev/null 2>&1
        $1
    " </dev/null 2>&1)" && BTRFS_RC=0 || BTRFS_RC=$?
}
run_btrfs_rc_live() { # no DRYRUN: closed stdin drives the confirm path
    BTRFS_OUT="$(timeout 20 zsh -f -c "
        STACK_COLOR=false
        source '$ZSH_DIR/cave-scripts.zsh' >/dev/null 2>&1
        $1
    " </dev/null 2>&1)" && BTRFS_RC=0 || BTRFS_RC=$?
}
btrfs_expect() { # $1 label, $2 actual, $3 expected
    if [ "$2" = "$3" ]; then
        passed=$((passed + 1))
        log_success "btrfs: $1"
    else
        failed=$((failed + 1))
        log_error "btrfs: $1 (got: $2)"
    fi
}

run_btrfs_rc 'cave-btrfs-scrub start --yes'
btrfs_expect "scrub dry-run echoes exact command" "$BTRFS_OUT" "+ sudo -n btrfs scrub start /"

run_btrfs_rc 'cave-btrfs-balance start --yes'
btrfs_expect "balance dry-run echoes exact command" "$BTRFS_OUT" "+ sudo -n btrfs balance start -dusage=50 -musage=50 /"

run_btrfs_rc 'cave-btrfs-snapshot create "suite probe"'
btrfs_expect "snapshot create dry-run echoes exact command" "$BTRFS_OUT" "+ sudo -n snapper -c home create --description suite probe"

run_btrfs_rc_live 'cave-btrfs-scrub start'
btrfs_expect "scrub aborts on closed stdin" "$BTRFS_OUT" "Start btrfs scrub on / (hours of IO)? [y/N] Aborted."

run_btrfs_rc 'cave-btrfs-subvol create /boot/grub'
if [ "$BTRFS_RC" -eq 1 ] && printf '%s' "$BTRFS_OUT" | grep -q "Refusing to touch /boot"; then
    passed=$((passed + 1)); log_success "btrfs: /boot refusal"
else
    failed=$((failed + 1)); log_error "btrfs: /boot refusal (rc=$BTRFS_RC, out: $BTRFS_OUT)"
fi

run_btrfs_rc 'cave-btrfs-scrub start --yes --turbo'
if [ "$BTRFS_RC" -eq 1 ] && printf '%s' "$BTRFS_OUT" | grep -q "Unknown option: --turbo"; then
    passed=$((passed + 1)); log_success "btrfs: scrub rejects unknown options even with --yes"
else
    failed=$((failed + 1)); log_error "btrfs: scrub unknown-option gate (rc=$BTRFS_RC, out: $BTRFS_OUT)"
fi

# --- Summary ---
print ""
print "=========================================="
if [ "$failed" -eq 0 ]; then
    print "  ALL PASSED ($passed checks)"
    print "=========================================="
    exit 0
else
    print "  FAILED: $failed checks failed ($passed passed)"
    print "=========================================="
    exit 1
fi
