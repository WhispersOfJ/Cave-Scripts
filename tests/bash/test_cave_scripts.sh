#!/usr/bin/env bash
# ============================================================================
# Cave-Scripts — Bash Offline Smoke Test
# ============================================================================
# Verifies the bash port (bash/) against the canonical registry
# (spec/functions.yaml): every registered command exists as a cave-* function,
# every stack-* alias forwarder exists and maps to the right cave-* target,
# all files parse, completions + aliases are current, and the offline unit
# tiers from thebearcave's tests/bash/test_bash_functions.sh are ported.
#
# Tiers:
#   syntax:        every bash/ file parses (bash -n)
#   load/define:   the loader defines the full cave-* surface
#   registry:      every functions.yaml row with a bash impl exists (cave-*)
#   aliases:       every stack-* forwarder exists and targets the right cave-*
#   helpers:       __helpers + fmt_* + guarded docker() wrapper present
#   completions:   generated file parses, registers cave-* + stack-*, current
#   timeout:       no bare curl -sf outside the wrapper (hang risk)
#   unit:          mocked renderer tests (missing-aired, requests, unwatched,
#                  arrival-notify --help, activity-feed arg guard,
#                  __stack_containers docker timeout, __arr_api_key message,
#                  stale key warning, clear-blocklist POST)
#   guard:         arg-requiring commands refuse cleanly with no args
#
# The live read-only tier stays in thebearcave (D11/D13 split) — this suite
# is the merge gate and is CI-safe with zero network/stack access.
#
# Usage:
#   ./tests/bash/test_cave_scripts.sh            # full offline suite
#   ./tests/bash/test_cave_scripts.sh --offline  # same (default; kept for parity)
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASH_DIR="$REPO_DIR/bash"
FUNC_DIR="$BASH_DIR/functions"
REGISTRY="$REPO_DIR/spec/functions.yaml"

cd "$REPO_DIR"

passed=0
failed=0

# Source the loader once so cave-* functions, stack-* aliases, fmt_* helpers,
# __helpers, and the docker wrapper are all defined for the checks.
# shellcheck disable=SC2034
STACK_COLOR=false
# shellcheck disable=SC1091
source "$BASH_DIR/cave-scripts.sh" >/dev/null 2>&1

assert_defined() {
    local name="$1" label="$2"
    if declare -F "$name" >/dev/null 2>&1; then
        passed=$((passed + 1))
        log_success "defines: $label"
    else
        failed=$((failed + 1))
        log_error "defines: $label (function missing)"
    fi
}

echo ""
echo "=========================================="
echo "  Cave-Scripts Bash Offline Smoke Test"
echo "=========================================="
echo ""

# --- Syntax tier: every bash/ file parses ---
log_info "Syntax checks (bash -n on every bash/ file)..."
load_fail=0
for f in "$FUNC_DIR"/*.sh "$BASH_DIR"/cave-scripts.sh "$BASH_DIR"/_aliases.sh \
         "$BASH_DIR"/completions/*.sh "$BASH_DIR"/scripts/gen-*.sh; do
    [ -f "$f" ] || continue
    if ! bash -n "$f" 2>/dev/null; then
        load_fail=$((load_fail + 1))
        log_error "syntax: $(basename "$f")"
    fi
done
if [ "$load_fail" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "all bash/ files parse (bash -n)"
else
    failed=$((failed + load_fail))
fi

# --- Load/define: cave-* commands found in function files ---
mapfile -t CAVE_CMDS < <(
    for f in "$FUNC_DIR"/cave-*.sh; do
        grep -oE '^cave-[a-z0-9-]+\(\)' "$f" 2>/dev/null | sed 's/()$//'
    done | sort -u
)
if [ "${#CAVE_CMDS[@]}" -eq 0 ]; then
    failed=$((failed + 1))
    log_error "no cave-* commands found in $FUNC_DIR"
else
    passed=$((passed + 1))
    log_success "${#CAVE_CMDS[@]} cave-* commands defined across function files"
fi

# --- Registry conformance: every row with a bash impl exists as cave-* ---
# Rows without an implementation yet (de/backup, built later in M3) are
# skipped; everything else must be defined in this bash port. btrfs landed
# in M3 and is now enforced like the media families.
log_info "Registry conformance (spec/functions.yaml rows → cave-* functions)..."
reg_missing=0
while IFS= read -r cave_name; do
    [ -n "$cave_name" ] || continue
    if ! declare -F "$cave_name" >/dev/null 2>&1; then
        reg_missing=$((reg_missing + 1))
        log_error "registry row missing from bash port: $cave_name"
    fi
done < <(python3 - "$REGISTRY" <<'PY'
import sys, yaml
reg = yaml.safe_load(open(sys.argv[1]))
for f in reg['functions']:
    if f['family'] not in ('de', 'backup'):
        print(f['name'])
PY
)
if [ "$reg_missing" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "every registry row (non-M3 families) has a cave-* function"
else
    failed=$((failed + reg_missing))
fi

# --- Registry conformance: every cave-* def has a registry row (no orphans) ---
log_info "Registry conformance (cave-* defs → registry rows, no orphans)..."
orphans=0
while IFS= read -r cave_name; do
    [ -n "$cave_name" ] || continue
    if ! python3 - "$REGISTRY" "$cave_name" <<'PY' | grep -q .
import sys, yaml
reg = yaml.safe_load(open(sys.argv[1]))
name = sys.argv[2]
for f in reg['functions']:
    if f['name'] == name:
        print(name)
        break
PY
    then
        orphans=$((orphans + 1))
        log_error "cave-* function has no registry row: $cave_name"
    fi
done < <(printf '%s\n' "${CAVE_CMDS[@]}")
if [ "$orphans" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "every cave-* def has a registry row (no orphans)"
else
    failed=$((failed + orphans))
fi

# --- Alias tier: every stack-* forwarder defined and targets the right cave-* ---
log_info "Alias conformance (_aliases.sh: stack-* → cave-* mapping)..."
alias_bad=0
while IFS= read -r alias_name; do
    [ -n "$alias_name" ] || continue
    # The alias line:  stack-<name>() { cave-<target> "$@"; }
    target="$(grep -E "^${alias_name}\\(\\) \\{ " "$BASH_DIR/_aliases.sh" \
        | sed -E "s/^${alias_name}\\(\\) \\{ (cave-[a-z0-9-]+) .*/\\1/")"
    if [ -z "$target" ]; then
        alias_bad=$((alias_bad + 1))
        log_error "alias missing forwarder or target: $alias_name"
        continue
    fi
    if ! declare -F "$alias_name" >/dev/null 2>&1; then
        alias_bad=$((alias_bad + 1))
        log_error "alias not defined in shell: $alias_name"
        continue
    fi
    if ! declare -F "$target" >/dev/null 2>&1; then
        alias_bad=$((alias_bad + 1))
        log_error "alias $alias_name targets missing function $target"
    fi
done < <(grep -oE '^stack-[a-z0-9-]+\(\)' "$BASH_DIR/_aliases.sh" | sed 's/()$//')
if [ "$alias_bad" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "every stack-* alias is defined and targets an existing cave-* function"
else
    failed=$((failed + alias_bad))
fi

# --- Alias tier: every cave-* command with a legacy name has its forwarder ---
# Mirror of gen-aliases.sh's scope: families born as cave-* with no legacy
# stack-* source (de/backup/btrfs) are exempt — D21 covers migrating names
# that existed as stack-*; inventing new stack-* names would pollute the
# legacy namespace. Everything else (media, core, sys) must forward.
log_info "Alias conformance (every legacy-named cave-* command has a stack-* forwarder)..."
missing_alias=0
while IFS= read -r cave_name; do
    [ -n "$cave_name" ] || continue
    family="$(python3 -c "
import sys, yaml
reg = yaml.safe_load(open('$REGISTRY'))
for f in reg['functions']:
    if f['name'] == '$cave_name':
        print(f['family'])
        break
")"
    case "$family" in
        de|backup|btrfs) continue ;;
    esac
    if ! grep -qE "^stack-.*\\(\\) \\{ ${cave_name} \"\\\$@\"; \\}" "$BASH_DIR/_aliases.sh"; then
        missing_alias=$((missing_alias + 1))
        log_error "cave-* command lacks a stack-* forwarder: $cave_name"
    fi
done < <(printf '%s\n' "${CAVE_CMDS[@]}")
if [ "$missing_alias" -eq 0 ]; then
    passed=$((passed + 1))
    log_success "every legacy-named cave-* command has a stack-* forwarder (D21)"
else
    failed=$((failed + missing_alias))
fi

# --- Alias functional check: stack-X invocation == cave-X invocation ---
# Pick a no-arg-safe command with deterministic output (cave-version prints a
# fixed line) and assert both spellings behave identically.
log_info "Alias functional check (stack-version ≡ cave-version)..."
ver_cave="$(STACK_COLOR=false cave-version 2>&1)" && vrc=0 || vrc=$?
ver_stack="$(STACK_COLOR=false stack-version 2>&1)" && src=0 || src=$?
if [ "$vrc" -eq "$src" ] && [ "$ver_cave" = "$ver_stack" ] && [ -n "$ver_cave" ]; then
    passed=$((passed + 1))
    log_success "stack-version output identical to cave-version"
else
    failed=$((failed + 1))
    log_error "alias mismatch (cave rc=$vrc [$ver_cave] vs stack rc=$src [$ver_stack])"
fi

# --- Helpers: fmt_*, __helpers, guarded docker() ---
for h in fmt_heading fmt_success fmt_error fmt_warning fmt_dim fmt_status_dot fmt_kv \
         __arr_api __arr_api_url __arr_api_key __stack_arr_app \
         __plex_api __plex_butler __seerr_api __nzbdav_api __stack_containers \
         __stack_curl; do
    assert_defined "$h" "$h"
done

if declare -F docker >/dev/null 2>&1; then
    passed=$((passed + 1))
    log_success "guarded docker() wrapper is defined"
else
    failed=$((failed + 1))
    log_error "guarded docker() wrapper is missing (loader did not define it)"
fi

# --- Completions: parse, register both spellings, no drift ---
log_info "Completion checks (generated file parses, registers, is current)..."
COMP_FILE="$BASH_DIR/completions/cave-completions.sh"
if [ ! -f "$COMP_FILE" ]; then
    failed=$((failed + 1))
    log_error "completion file missing: $COMP_FILE"
else
    if bash -n "$COMP_FILE" 2>/dev/null; then
        passed=$((passed + 1))
        log_success "completion file parses (bash -n)"
    else
        failed=$((failed + 1))
        log_error "completion file fails to parse"
    fi
    if declare -F __stack_complete >/dev/null 2>&1; then
        passed=$((passed + 1))
        log_success "__stack_complete is defined"
    else
        failed=$((failed + 1))
        log_error "__stack_complete is not defined (completion file did not load)"
    fi
    # Both spellings registered: cave-* names AND their stack-* aliases.
    reg_cave="$(grep 'complete -F' "$COMP_FILE" | grep -oE '\bcave-[a-z0-9-]+' | sort -u | wc -l | tr -d ' ')"
    reg_stack="$(grep 'complete -F' "$COMP_FILE" | grep -oE '\bstack-[a-z0-9-]+' | sort -u | wc -l | tr -d ' ')"
    if [ "$reg_cave" -ge 128 ] && [ "$reg_stack" -ge 128 ]; then
        passed=$((passed + 1))
        log_success "completions register $reg_cave cave-* + $reg_stack stack-* spellings"
    else
        failed=$((failed + 1))
        log_error "completion registration incomplete (cave=$reg_cave stack=$reg_stack)"
    fi
fi

log_info "completion drift check (gen-bash-completions.sh --check)..."
if bash "$BASH_DIR/scripts/gen-bash-completions.sh" --check >/dev/null 2>&1; then
    passed=$((passed + 1))
    log_success "completions are current (no drift)"
else
    failed=$((failed + 1))
    log_error "completions are out of date — run gen-bash-completions.sh"
fi

log_info "alias drift check (gen-aliases.sh --check)..."
if bash "$BASH_DIR/scripts/gen-aliases.sh" --check >/dev/null 2>&1; then
    passed=$((passed + 1))
    log_success "aliases are current (no drift)"
else
    failed=$((failed + 1))
    log_error "aliases are out of date — run gen-aliases.sh"
fi

# --- Timeout coverage: every curl API call routes through __stack_curl ---
log_info "timeout coverage check (no bare curl -sf outside the wrapper)..."
bare="$(grep -rn 'curl -sf' "$FUNC_DIR" 2>/dev/null \
    | grep -v '__stack_curl' \
    | grep -v "'curl'" || true)"
if [ -z "$bare" ]; then
    passed=$((passed + 1))
    log_success "every curl -sf site routes through __stack_curl"
else
    failed=$((failed + 1))
    log_error "bare curl -sf sites remain (hang risk):"
    printf '%s\n' "$bare" | sed 's/^/         - /' | head -10
fi

# --- Unit: cave-arr-missing-aired sonarr renderer (offline) ---
log_info "unit: cave-arr-missing-aired sonarr renderer (mock wanted/missing)..."
mock_file="$(mktemp)"
trap 'rm -f "$mock_file"' EXIT
printf '%s' '{"records":[{"seriesId":42,"seasonNumber":3,"episodeNumber":7,"title":"The Test"},{"seriesId":7,"seasonNumber":1,"episodeNumber":2,"title":"Second"}],"totalRecords":3}' > "$mock_file"
unit_out="$(SONARR_URL='http://127.0.0.1:1' SONARR_API_KEY='mock-key' STACK_COLOR=false bash -c '
    MOCK_FILE="$2"
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    __stack_curl() { cat "$MOCK_FILE"; }
    "$3" sonarr 5
' _ "$BASH_DIR/cave-scripts.sh" "$mock_file" cave-arr-missing-aired 2>&1)" && rc=0 || rc=$?
rm -f "$mock_file"
if [ "$rc" -eq 0 ] \
    && printf '%s' "$unit_out" | grep -q '? S03E07 The Test' \
    && printf '%s' "$unit_out" | grep -q '? S01E02 Second' \
    && printf '%s' "$unit_out" | grep -q '... and 1 more' \
    && ! printf '%s' "$unit_out" | grep -q 'Cannot reach'; then
    passed=$((passed + 1))
    log_success "unit: missing-aired renderer degrades to '?' titles on dead series URL"
else
    failed=$((failed + 1))
    log_error "unit: missing-aired renderer output unexpected (rc=$rc):"
    printf '%s\n' "$unit_out" | tail -8 | sed 's/^/         /'
fi

# --- Unit: cave-arr-missing-aired radarr renderer (offline) ---
log_info "unit: cave-arr-missing-aired radarr renderer (mock movies)..."
radarr_mock="$(mktemp)"
printf '%s' '[{"title":"Available Miss","year":2020,"monitored":true,"hasFile":false,"isAvailable":true},{"title":"Not Yet Aired","year":2025,"monitored":true,"hasFile":false,"isAvailable":false},{"title":"Already Have","year":2019,"monitored":true,"hasFile":true,"isAvailable":true},{"title":"Unmonitored","year":2021,"monitored":false,"hasFile":false,"isAvailable":true},{"title":"Second Miss","year":2024,"monitored":true,"hasFile":false,"isAvailable":true}]' > "$radarr_mock"
radarr_out="$(RADARR_API_KEY='mock-key' STACK_COLOR=false bash -c '
    MOCK_FILE="$2"
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    __stack_curl() { cat "$MOCK_FILE"; }
    "$3" radarr 1
' _ "$BASH_DIR/cave-scripts.sh" "$radarr_mock" cave-arr-missing-aired 2>&1)" && rc=0 || rc=$?
rm -f "$radarr_mock"
if [ "$rc" -eq 0 ] \
    && printf '%s' "$radarr_out" | grep -q 'Available Miss (2020)' \
    && printf '%s' "$radarr_out" | grep -q '... and 1 more' \
    && printf '%s' "$radarr_out" | grep -q '2 item(s) missing.' \
    && ! printf '%s' "$radarr_out" | grep -q 'Not Yet Aired' \
    && ! printf '%s' "$radarr_out" | grep -q 'Already Have' \
    && ! printf '%s' "$radarr_out" | grep -q 'Unmonitored' \
    && ! printf '%s' "$radarr_out" | grep -q 'Cannot reach'; then
    passed=$((passed + 1))
    log_success "unit: missing-aired radarr filter keeps monitored+missing+available only"
else
    failed=$((failed + 1))
    log_error "unit: missing-aired radarr filter unexpected (rc=$rc):"
    printf '%s\n' "$radarr_out" | tail -8 | sed 's/^/         /'
fi

# --- Unit: cave-requests Seerr renderer (offline) ---
log_info "unit: cave-requests Seerr renderer (mock requests)..."
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
seerr_out="$(SEERR_API_KEY='mock-key' STACK_COLOR=false bash -c '
    COUNTS="$2" LIST="$3"
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    __seerr_api() {
        case "$2" in
            *"request/count"*) cat "$COUNTS" ;;
            *) cat "$LIST" ;;
        esac
    }
    "$4" 10
' _ "$BASH_DIR/cave-scripts.sh" "$seerr_counts_mock" "$seerr_list_mock" cave-requests 2>&1)" && rc=0 || rc=$?
rm -f "$seerr_counts_mock" "$seerr_list_mock"
if [ "$rc" -eq 0 ] \
    && printf '%s' "$seerr_out" | grep -q 'total=10 pending=0 approved=2 declined=1 failed=0' \
    && printf '%s' "$seerr_out" | grep -q '\[movie\] tmdb:41264 - by RequesterA (processing)' \
    && printf '%s' "$seerr_out" | grep -q '\[tv\] tvdb:55 - by RequesterF (pending)' \
    && printf '%s' "$seerr_out" | grep -q 'Watchable Now - by RequesterD (available now)' \
    && ! printf '%s' "$seerr_out" | grep -q 'Closed And Available' \
    && ! printf '%s' "$seerr_out" | grep -q 'Declined Flick' \
    && ! printf '%s' "$seerr_out" | grep -q 'Failed Show' \
    && ! printf '%s' "$seerr_out" | grep -q 'RequesterB'; then
    passed=$((passed + 1))
    log_success "unit: requests renderer surfaces open + available-now, hides closed"
else
    failed=$((failed + 1))
    log_error "unit: requests renderer output unexpected (rc=$rc):"
    printf '%s\n' "$seerr_out" | tail -10 | sed 's/^/         /'
fi

# --- Unit: cave-unwatched Plex renderer (offline) ---
log_info "unit: cave-unwatched Plex renderer (mock sections)..."
plex_sections_mock="$(mktemp)"
plex_items_mock="$(mktemp)"
printf '%s' '{"MediaContainer":{"Directory":['\
'{"key":"1","title":"Movies","type":"movie"},'\
'{"key":"3","title":"Music","type":"artist"}]}}' > "$plex_sections_mock"
printf '{"MediaContainer":{"Metadata":[{"title":"Fresh Flick","year":2026,"addedAt":%s},{"title":"Old Flick","year":1985,"addedAt":%s}]}}' \
    "$(date -d '-2 days' +%s)" "$(date -d '-40 days' +%s)" > "$plex_items_mock"
plex_out="$(PLEX_TOKEN='mock-token' STACK_COLOR=false bash -c '
    SECTIONS="$2" ITEMS="$3"
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    __stack_curl() {
        local url="${*: -1}"
        case "$url" in
            *"/library/sections?"*) cat "$SECTIONS" ;;
            *"/library/sections/"*"/unwatched?"*) cat "$ITEMS" ;;
        esac
    }
    "$4" 5
' _ "$BASH_DIR/cave-scripts.sh" "$plex_sections_mock" "$plex_items_mock" cave-unwatched 2>&1)" && rc=0 || rc=$?
rm -f "$plex_sections_mock" "$plex_items_mock"
if [ "$rc" -eq 0 ] \
    && printf '%s' "$plex_out" | grep -q '\[Movies\]' \
    && printf '%s' "$plex_out" | grep -q 'Fresh Flick (2026) - added 2d ago' \
    && printf '%s' "$plex_out" | grep -q '(1 of 2 unwatched added within the last 30 days)' \
    && ! printf '%s' "$plex_out" | grep -q '\[Music\]' \
    && ! printf '%s' "$plex_out" | grep -q 'Old Flick'; then
    passed=$((passed + 1))
    log_success "unit: unwatched renderer lists 30-day-fresh, skips non-media libraries"
else
    failed=$((failed + 1))
    log_error "unit: unwatched renderer output unexpected (rc=$rc):"
    printf '%s\n' "$plex_out" | tail -10 | sed 's/^/         /'
fi

# --- Unit: cave-arrival-notify --help prints usage (offline) ---
log_info "unit: cave-arrival-notify --help prints usage..."
arr_help_out="$(bash -c '
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    "$2" --help
' _ "$BASH_DIR/cave-scripts.sh" cave-arrival-notify 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$arr_help_out" | grep -q 'Usage: cave-arrival-notify'; then
    passed=$((passed + 1))
    log_success "unit: arrival-notify --help prints usage (exit 0)"
else
    failed=$((failed + 1))
    log_error "unit: arrival-notify --help unexpected (rc=$rc): [$arr_help_out]"
fi

# --- Unit: cave-activity-feed refuses >1 arg (offline) ---
log_info "unit: cave-activity-feed refuses extra args..."
feed_usage_out="$(bash -c '
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    "$2" 5 bogus
' _ "$BASH_DIR/cave-scripts.sh" cave-activity-feed 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$feed_usage_out" | grep -q 'Usage: cave-activity-feed'; then
    passed=$((passed + 1))
    log_success "unit: activity-feed refuses >1 arg with usage (exit 1)"
else
    failed=$((failed + 1))
    log_error "unit: activity-feed usage unexpected (rc=$rc): [$feed_usage_out]"
fi

# --- Unit: __stack_containers docker timeout (offline) ---
log_info "unit: __stack_containers returns within STACK_DOCKER_TIMEOUT..."
fake_bin="$(mktemp -d)"
printf '#!/bin/bash\nsleep 30\n' > "$fake_bin/docker"
chmod +x "$fake_bin/docker"
docker_t0=$SECONDS
docker_out="$(PATH="$fake_bin:$PATH" STACK_DOCKER_TIMEOUT=2 __stack_containers 2>&1)" && rc=0 || rc=$?
docker_elapsed=$((SECONDS - docker_t0))
rm -rf "$fake_bin"
if { [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; } \
    && [ "$docker_elapsed" -le 5 ] && [ -z "$docker_out" ]; then
    passed=$((passed + 1))
    log_success "unit: __stack_containers cut at STACK_DOCKER_TIMEOUT (${docker_elapsed}s, empty output)"
else
    failed=$((failed + 1))
    log_error "unit: __stack_containers docker timeout (rc=$rc, ${docker_elapsed}s, output=[$docker_out])"
fi

# --- Unit: __arr_api_key unset message names the real var (offline) ---
log_info "unit: __arr_api_key unset message names SONARR_API_KEY..."
key_msg="$(SONARR_API_KEY='' STACK_COLOR=false bash -c '
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    unset SONARR_API_KEY
    __arr_api_key sonarr
' _ "$BASH_DIR/cave-scripts.sh" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 1 ] \
    && printf '%s' "$key_msg" | grep -q 'SONARR_API_KEY' \
    && ! printf '%s' "$key_msg" | grep -q 'sonarr_API_KEY'; then
    passed=$((passed + 1))
    log_success "unit: __arr_api_key unset message names SONARR_API_KEY"
else
    failed=$((failed + 1))
    log_error "unit: __arr_api_key unset message unexpected (rc=$rc): [$key_msg]"
fi

# --- Unit: stale arr key/URL warning (offline) ---
log_info "unit: stale arr key warning fires on mismatch, silent on match..."
stale_tmp="$(mktemp -d)"
printf 'SONARR_API_KEY=real-key\nRADARR_URL=http://real:7878\n' > "$stale_tmp/.env"
stale_out="$(SONARR_API_KEY='stale-key' RADARR_URL='http://real:7878' \
    BEARCAVE_REPO_DIR="$stale_tmp" STACK_COLOR=false bash -c '
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' _ "$BASH_DIR/cave-scripts.sh" 2>&1)" && rc=0 || rc=$?
match_out="$(SONARR_API_KEY='real-key' RADARR_URL='http://real:7878' \
    BEARCAVE_REPO_DIR="$stale_tmp" STACK_COLOR=false bash -c '
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' _ "$BASH_DIR/cave-scripts.sh" 2>&1)" && rc=0 || rc=$?
noenv_out="$(SONARR_API_KEY='stale-key' BEARCAVE_REPO_DIR="$(mktemp -d)" \
    STACK_COLOR=false bash -c '
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' _ "$BASH_DIR/cave-scripts.sh" 2>&1)" && rc=0 || rc=$?
rm -rf "$stale_tmp"
if printf '%s' "$stale_out" | grep -q 'SONARR_API_KEY' \
    && ! printf '%s' "$stale_out" | grep -q 'RADARR_URL' \
    && [ -z "$match_out" ] && [ -z "$noenv_out" ]; then
    passed=$((passed + 1))
    log_success "unit: stale arr key warning fires on mismatch, silent on match"
else
    failed=$((failed + 1))
    log_error "unit: stale arr key warning unexpected (stale=[$stale_out] match=[$match_out] noenv=[$noenv_out])"
fi

# --- Unit: cave-arr-clear-blocklist posts the ClearBlocklist command ---
log_info "unit: cave-arr-clear-blocklist posts the ClearBlocklist command..."
clear_tmp="$(mktemp)"
CAPTURE_FILE="$clear_tmp" RADARR_API_KEY='mock-key' \
    RADARR_URL='http://127.0.0.1:1' STACK_COLOR=false bash -c '
    # shellcheck disable=SC1091
    source "$1" >/dev/null 2>&1
    __stack_curl() { printf "%s" "$*" > "$CAPTURE_FILE"; return 0; }
    cave-arr-clear-blocklist radarr
' _ "$BASH_DIR/cave-scripts.sh" >/dev/null 2>&1; rc=$?
clear_capture="$(cat "$clear_tmp")"
rm -f "$clear_tmp"
if [ "$rc" -eq 0 ] \
    && printf '%s' "$clear_capture" | grep -q -- '-X POST' \
    && printf '%s' "$clear_capture" | grep -q 'api/v3/command' \
    && printf '%s' "$clear_capture" | grep -q 'ClearBlocklist' \
    && ! printf '%s' "$clear_capture" | grep -q -- '-X DELETE'; then
    passed=$((passed + 1))
    log_success "unit: clear-blocklist posts the ClearBlocklist command"
else
    failed=$((failed + 1))
    log_error "unit: clear-blocklist invocation unexpected (rc=$rc): [$clear_capture]"
fi

# --- Guard tier: mutating/arg-requiring commands refuse cleanly with no args ---
log_info "Guard tier (no-args invocations must print usage and exit cleanly)..."
run_guard() {
    local name="$1"
    local output rc
    output="$(timeout 20 bash -c "
        STACK_COLOR=false
        source '$BASH_DIR/cave-scripts.sh' >/dev/null 2>&1
        $name
    " </dev/null 2>&1)" && rc=0 || rc=$?
    if [ "$rc" -le 1 ] && [ -n "$output" ]; then
        passed=$((passed + 1))
        log_success "guard: $name (exit $rc, refused with output)"
    else
        failed=$((failed + 1))
        log_error "guard: $name (exit $rc, $([ -n "$output" ] && echo 'had output' || echo 'no output'))"
        printf '%s\n' "$output" | tail -3 | sed 's/^/         /'
    fi
}

for cmd in \
    cave-arr cave-arr-backlog cave-arr-blocklist cave-arr-clear-blocklist \
    cave-arr-import cave-arr-import-all cave-arr-import-candidates \
    cave-arr-import-starvation cave-arr-logs cave-arr-missing-aired \
    cave-arr-queue-errors cave-arr-recently-added cave-arr-toggle-search \
    cave-container cave-cutoff-unmet cave-disk-reclaim cave-import-lists \
    cave-loop-candidates cave-loop-exclude cave-loop-unmonitor \
    cave-radarr-prune cave-sonarr-prune cave-worktree \
    cave-btrfs-snapshot cave-btrfs-subvol cave-btrfs-scrub \
    cave-btrfs-balance cave-btrfs-snapper; do
    if printf '%s\n' "${CAVE_CMDS[@]}" | grep -qx "$cmd"; then
        run_guard "$cmd"
    fi
done

# cave-restart-all prompts for confirmation; with no stdin it must decline.
if printf '%s\n' "${CAVE_CMDS[@]}" | grep -qx cave-restart-all; then
    run_guard cave-restart-all
fi

# --- Btrfs tier (M3): dry-run echo-before-exec, /boot refusal, closed-stdin abort ---
log_info "Btrfs tier (dry-run echo-before-exec, /boot refusal, closed-stdin abort)..."
run_btrfs_dry() { # exact stdout of a CAVE_BTRFS_DRYRUN=1 invocation
    timeout 20 bash -c "
        STACK_COLOR=false
        CAVE_BTRFS_DRYRUN=1
        source '$BASH_DIR/cave-scripts.sh' >/dev/null 2>&1
        $1
    " </dev/null 2>&1
}
run_btrfs_live() { # no DRYRUN: closed stdin drives the confirm path
    timeout 20 bash -c "
        STACK_COLOR=false
        source '$BASH_DIR/cave-scripts.sh' >/dev/null 2>&1
        $1
    " </dev/null 2>&1
}
run_btrfs_rc() { # sets BTRFS_OUT + BTRFS_RC (set -e-safe capture of a failing command)
    BTRFS_OUT="$(timeout 20 bash -c "
        STACK_COLOR=false
        CAVE_BTRFS_DRYRUN=1
        source '$BASH_DIR/cave-scripts.sh' >/dev/null 2>&1
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

out="$(run_btrfs_dry 'cave-btrfs-scrub start --yes')"
btrfs_expect "scrub dry-run echoes exact command" "$out" "+ sudo -n btrfs scrub start /"

out="$(run_btrfs_dry 'cave-btrfs-balance start --yes')"
btrfs_expect "balance dry-run echoes exact command" "$out" "+ sudo -n btrfs balance start -dusage=50 -musage=50 /"

out="$(run_btrfs_dry 'cave-btrfs-snapshot create "suite probe"')"
btrfs_expect "snapshot create dry-run echoes exact command" "$out" "+ sudo -n snapper -c home create --description suite probe"

out="$(run_btrfs_live 'cave-btrfs-scrub start')" || true
btrfs_expect "scrub aborts on closed stdin" "$out" "Start btrfs scrub on / (hours of IO)? [y/N] Aborted."

out="$(run_btrfs_live 'cave-btrfs-snapshot create x')" || true
btrfs_expect "snapshot create aborts on closed stdin" "$out" "Create @home snapshot 'x'? [y/N] Aborted."

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

run_btrfs_rc 'cave-btrfs-snapshot delete abc'
if [ "$BTRFS_RC" -eq 1 ] && printf '%s' "$BTRFS_OUT" | grep -q "must be numeric"; then
    passed=$((passed + 1)); log_success "btrfs: snapshot delete numeric validation"
else
    failed=$((failed + 1)); log_error "btrfs: snapshot delete numeric validation (rc=$BTRFS_RC, out: $BTRFS_OUT)"
fi

# --- Summary ---
echo ""
echo "=========================================="
if [ "$failed" -eq 0 ]; then
    echo "  ALL PASSED ($passed checks)"
    echo "=========================================="
    exit 0
else
    echo "  FAILED: $failed checks failed ($passed passed)"
    echo "=========================================="
    exit 1
fi