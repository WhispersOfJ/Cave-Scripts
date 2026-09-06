#!/usr/bin/env fish
# ============================================================================
# Cave-Scripts — Fish Offline Smoke Test
# ============================================================================
# Verifies the fish port (fish/) against the canonical registry
# (spec/functions.yaml) and against the bash port (bash/) itself:
# every registered command exists as a cave-* function, every stack-* alias
# forwarder exists and maps to the right cave-* target, all fish files parse
# (fish -n), the completions are current and register both spellings, and —
# the Demo-2 crown check — the fish port produces byte-identical output to
# the bash port for the same command (cave-help, cave-version, and the
# mocked renderer units run under BOTH shells and diffed).
#
# Tiers:
#   syntax:        every fish/ file parses (fish -n; generators stay bash)
#   load/define:   the fish loader defines the full cave-* surface (128)
#   registry:      every functions.yaml row with a fish impl exists (cave-*)
#   aliases:       fish/_aliases.fish loads; every stack-* forwarder targets
#                  the right cave-* (same mapping as bash)
#   helpers:       __helpers + fmt_* + guarded docker() present under fish
#   completions:   cave-completions.fish parses, registers cave-* + stack-*,
#                  file current (gen-fish-completions.sh --check)
#   parity:        byte-identical output vs the bash port for cave-version,
#                  cave-help, and the mocked renderer fixtures
#   unit:          mocked renderer tests (missing-aired sonarr/radarr,
#                  requests, unwatched) with the fish loader
#   guard:         arg-requiring commands refuse cleanly with no args
#
# The live read-only tier stays in thebearcave (D11/D13 split) — this suite
# is the merge gate and is CI-safe with zero network/stack access.
#
# Usage:
#   fish tests/fish/test_cave_scripts.fish
# ============================================================================
set -l SCRIPT_DIR (dirname (status filename))
set -x REPO_DIR (dirname (dirname "$SCRIPT_DIR"))
set -x FISH_DIR "$REPO_DIR/fish"
set -x FUNC_DIR "$FISH_DIR/functions"
set -x BASH_DIR "$REPO_DIR/bash"
set -x REGISTRY "$REPO_DIR/spec/functions.yaml"

# Isolate from the real HOME: sourcing the loader exports env vars from
# $BEARCAVE_REPO_DIR/.env — redirect HOME so the test never touches (or
# poisons) the user's real config, and point BEARCAVE_REPO_DIR at this repo
# so repo-relative commands (cave-version's git log line) resolve identically
# in every subprocess — and stay CI-safe.
set -x TEST_HOME (mktemp -d)
set -x HOME "$TEST_HOME"
set -x BEARCAVE_REPO_DIR "$REPO_DIR"

set passed 0
set failed 0

function log_info
    set_color blue; echo "[INFO] $argv"; set_color normal
end
function log_success
    set_color green; echo "[PASS] $argv"; set_color normal
end
function log_warning
    set_color yellow; echo "[WARN] $argv"; set_color normal
end
function log_error
    set_color red; echo "[FAIL] $argv"; set_color normal
end

function cleanup --on-event fish_exit
    rm -rf "$TEST_HOME"
end

cd "$REPO_DIR"

echo ""
echo "=========================================="
echo "  Cave-Scripts Fish Offline Smoke Test"
echo "=========================================="
echo ""

# --- Syntax tier: every fish file parses ---
log_info "Syntax checks (fish -n on every fish/ file)..."
set load_fail 0
for f in "$FUNC_DIR"/*.fish "$FISH_DIR"/cave-scripts.fish "$FISH_DIR"/completions/*.fish
    test -f "$f"; or continue
    if not fish -n "$f" >/dev/null 2>&1
        set load_fail (math $load_fail + 1)
        log_error "syntax: "(string replace "$REPO_DIR/" "" -- "$f")
    end
end
# The generators are bash scripts (they drive the shared parser) —
# syntax-check them with bash, exactly as the bash suite does.
for f in "$FISH_DIR"/scripts/gen-*.sh
    test -f "$f"; or continue
    if not bash -n "$f" >/dev/null 2>&1
        set load_fail (math $load_fail + 1)
        log_error "syntax (generator): "(string replace "$REPO_DIR/" "" -- "$f")
    end
end
if test "$load_fail" -eq 0
    set passed (math $passed + 1)
    log_success "all fish/ files parse (fish -n) + generators parse (bash -n)"
else
    set failed (math $failed + $load_fail)
end

# --- Load the fish loader once in THIS shell so cave-*/stack-*/fmt_*/docker
#     are defined for the in-shell checks. Silence the stale-key probe. ---
set STACK_COLOR false
set -x STACK_COLOR false
source "$FISH_DIR/cave-scripts.fish" >/dev/null 2>&1

# --- Load/define: cave-* commands found in function files ---
set CAVE_CMDS ()
for f in "$FUNC_DIR"/cave-*.fish
    for c in (grep -oE '^function cave-[a-z0-9-]+' "$f" 2>/dev/null | sed 's/^function //')
        set -a CAVE_CMDS "$c"
    end
end
set CAVE_CMDS (printf '%s\n' $CAVE_CMDS | sort -u | string match -r '^cave-[a-z0-9-]+$')
# Legacy-alias surface = commands whose registry family has a stack-* source
# (media/core/sys). Families born as cave-* (de/backup/btrfs) have no legacy
# alias and are excluded from count assertions against the alias file.
set LEGACY_CMDS ()
for cmd in $CAVE_CMDS
    set -l family (python3 -c "
import sys, yaml
reg = yaml.safe_load(open(sys.argv[2]))
for f in reg['functions']:
    if f['name'] == sys.argv[1]:
        print(f['family'])
        break
" "$cmd" "$REGISTRY" 2>/dev/null)
    if not contains "$family" de backup btrfs
        set -a LEGACY_CMDS "$cmd"
    end
end
if test (count $CAVE_CMDS) -eq 0
    set failed (math $failed + 1)
    log_error "no cave-* commands found in $FUNC_DIR"
else
    set passed (math $passed + 1)
    log_success (count $CAVE_CMDS)" cave-* commands defined across function files"
end

# --- Load/define: every cave-* source file defines a function in-shell ---
log_info "Load check (sourced functions are callable)..."
set undef 0
for cmd in $CAVE_CMDS
    if not functions -q "$cmd"
        set undef (math $undef + 1)
        log_error "source-defined function missing in shell: $cmd"
    end
end
if test "$undef" -eq 0
    set passed (math $passed + 1)
    log_success "every cave-* command is callable after sourcing the loader"
else
    set failed (math $failed + $undef)
end

# --- Registry conformance: every row with a fish impl exists as cave-* ---
# Rows without a stack-* source yet (de/backup/btrfs, built in M3) are skipped.
log_info "Registry conformance (spec/functions.yaml rows → cave-* functions)..."
set reg_missing 0
set reg_rows (python3 -c '
import sys, yaml
reg = yaml.safe_load(open(sys.argv[1]))
for f in reg["functions"]:
    if f["family"] not in ("de", "backup"):
        print(f["name"])
' "$REGISTRY")
for cave_name in $reg_rows
    test -n "$cave_name"; or continue
    if not functions -q "$cave_name"
        set reg_missing (math $reg_missing + 1)
        log_error "registry row missing from fish port: $cave_name"
    end
end
if test "$reg_missing" -eq 0
    set passed (math $passed + 1)
    log_success "every registry row (non-de/backup families) has a cave-* function"
else
    set failed (math $failed + $reg_missing)
end

# --- Btrfs tier (M3): dry-run echo-before-exec, /boot refusal, closed-stdin abort ---
log_info "Btrfs tier (dry-run echo-before-exec, /boot refusal, closed-stdin abort)..."
function run_btrfs_rc --argument-names snippet --description "dry-run btrfs probe"
    set -g BTRFS_OUT (timeout 20 fish -N -c "
        set -gx STACK_COLOR false
        set -gx CAVE_BTRFS_DRYRUN 1
        source '$FISH_DIR/cave-scripts.fish' >/dev/null 2>&1
        $snippet
    " </dev/null 2>&1)
    set -g BTRFS_RC $status
end
function run_btrfs_rc_live --argument-names snippet --description "live-confirm btrfs probe"
    set -g BTRFS_OUT (timeout 20 fish -N -c "
        set -gx STACK_COLOR false
        source '$FISH_DIR/cave-scripts.fish' >/dev/null 2>&1
        $snippet
    " </dev/null 2>&1)
    set -g BTRFS_RC $status
end
function btrfs_expect --argument-names label actual expected
    if test "$actual" = "$expected"
        set -g passed (math $passed + 1)
        log_success "btrfs: $label"
    else
        set -g failed (math $failed + 1)
        log_error "btrfs: $label (got: $actual)"
    end
end

run_btrfs_rc 'cave-btrfs-scrub start --yes'
btrfs_expect "scrub dry-run echoes exact command" "$BTRFS_OUT" "+ sudo -n btrfs scrub start /"

run_btrfs_rc 'cave-btrfs-balance start --yes'
btrfs_expect "balance dry-run echoes exact command" "$BTRFS_OUT" "+ sudo -n btrfs balance start -dusage=50 -musage=50 /"

run_btrfs_rc 'cave-btrfs-snapshot create "suite probe"'
btrfs_expect "snapshot create dry-run echoes exact command" "$BTRFS_OUT" "+ sudo -n snapper -c home create --description suite probe"

run_btrfs_rc_live 'cave-btrfs-scrub start'
btrfs_expect "scrub aborts on closed stdin" "$BTRFS_OUT" "Start btrfs scrub on / (hours of IO)? [y/N] Aborted."

run_btrfs_rc 'cave-btrfs-subvol create /boot/grub'
if test "$BTRFS_RC" -eq 1; and string match -q "*Refusing to touch /boot*" -- "$BTRFS_OUT"
    set -g passed (math $passed + 1); log_success "btrfs: /boot refusal"
else
    set -g failed (math $failed + 1); log_error "btrfs: /boot refusal (rc=$BTRFS_RC, out: $BTRFS_OUT)"
end

run_btrfs_rc 'cave-btrfs-scrub start --yes --turbo'
if test "$BTRFS_RC" -eq 1; and string match -q "*Unknown option: --turbo*" -- "$BTRFS_OUT"
    set -g passed (math $passed + 1); log_success "btrfs: scrub rejects unknown options even with --yes"
else
    set -g failed (math $failed + 1); log_error "btrfs: scrub unknown-option gate (rc=$BTRFS_RC, out: $BTRFS_OUT)"
end

# --- Registry conformance: every cave-* def has a registry row (no orphans) ---
log_info "Registry conformance (cave-* defs → registry rows, no orphans)..."
set orphans 0
for cave_name in $CAVE_CMDS
    test -n "$cave_name"; or continue
    set -l hit (python3 -c '
import sys, yaml
reg = yaml.safe_load(open(sys.argv[1]))
for f in reg["functions"]:
    if f["name"] == sys.argv[2]:
        print(f["name"])
        break
' "$REGISTRY" "$cave_name")
    if test -z "$hit"
        set orphans (math $orphans + 1)
        log_error "cave-* function has no registry row: $cave_name"
    end
end
if test "$orphans" -eq 0
    set passed (math $passed + 1)
    log_success "every cave-* def has a registry row (no orphans)"
else
    set failed (math $failed + $orphans)
end

# --- Alias tier: fish/_aliases.fish loads and matches bash ---
log_info "Alias conformance (fish/_aliases.fish: stack-* → cave-* mapping)..."
set ALIAS_FILE "$FISH_DIR/_aliases.fish"
if not test -f "$ALIAS_FILE"
    set failed (math $failed + 1)
    log_error "fish alias file missing: $ALIAS_FILE"
else
    set alias_bad 0
    set ALIASES (grep -oE '^function stack-[a-z0-9-]+' "$ALIAS_FILE" | sed 's/^function //' | sort -u)
    if test (count $ALIASES) -ne (count $LEGACY_CMDS)
        set alias_bad (math $alias_bad + 1)
        log_error "alias count ("(count $ALIASES)") != legacy cave-* count ("(count $LEGACY_CMDS)")"
    end
    for alias_name in $ALIASES
        test -n "$alias_name"; or continue
        # Alias line:  function stack-<name>; cave-<target> $argv; end
        set -l target (grep -E "^function $alias_name;" "$ALIAS_FILE" \
            | sed -E "s/^function $alias_name; (cave-[a-z0-9-]+) \\\$argv; end/\1/")
        if test -z "$target"
            set alias_bad (math $alias_bad + 1)
            log_error "alias missing forwarder or target: $alias_name"
            continue
        end
        if not functions -q "$alias_name"
            set alias_bad (math $alias_bad + 1)
            log_error "alias not defined in fish: $alias_name"
            continue
        end
        if not functions -q "$target"
            set alias_bad (math $alias_bad + 1)
            log_error "alias $alias_name targets missing function $target"
        end
    end
    # Cross-check: the fish alias set exactly matches the bash alias set.
    set -l bash_aliases (grep -oE '^stack-[a-z0-9-]+\(\)' "$BASH_DIR/_aliases.sh" | sed 's/()//' | sort -u)
    if not diff -q (printf '%s\n' $ALIASES | psub) (printf '%s\n' $bash_aliases | psub) >/dev/null
        set alias_bad (math $alias_bad + 1)
        log_error "fish alias set diverges from bash/_aliases.sh"
    end
    if test "$alias_bad" -eq 0
        set passed (math $passed + 1)
        log_success "(count $ALIASES) stack-* aliases defined in fish, all targets resolve, set == bash"
    else
        set failed (math $failed + $alias_bad)
    end
end

# --- Alias functional check: stack-X invocation == cave-X invocation ---
log_info "Alias functional check (stack-version ≡ cave-version in fish)..."
set ver_cave (STACK_COLOR=false cave-version 2>&1); set vrc $status
set ver_stack (STACK_COLOR=false stack-version 2>&1); set src_rc $status
if test "$vrc" -eq "$src_rc"; and test "$ver_cave" = "$ver_stack"; and test -n "$ver_cave"
    set passed (math $passed + 1)
    log_success "stack-version output identical to cave-version in fish"
else
    set failed (math $failed + 1)
    log_error "alias mismatch (cave rc=$vrc vs stack rc=$src_rc)"
end

# --- Helpers: fmt_*, __helpers, guarded docker() under fish ---
function assert_defined --argument-names name label
    if functions -q "$name"
        set -g passed (math $passed + 1)
        log_success "defines: $label"
    else
        set -g failed (math $failed + 1)
        log_error "defines: $label (function missing)"
    end
end

for h in fmt_heading fmt_success fmt_error fmt_warning fmt_dim fmt_status_dot fmt_kv \
         __arr_api __arr_api_url __arr_api_key __stack_arr_app \
         __plex_api __plex_butler __seerr_api __nzbdav_api __stack_containers \
         __stack_curl __stack_metadata __bearcave_load_env __bearcave_warn_stale_keys
    assert_defined "$h" "$h"
end

if functions -q docker
    set passed (math $passed + 1)
    log_success "guarded docker() wrapper is defined under fish"
else
    set failed (math $failed + 1)
    log_error "guarded docker() wrapper is missing (loader did not define it)"
end

# --- Demo-2 regression: __helpers.fish must default the API timeout budgets ---
# The 2026-09-05 live demo caught fish __helpers.fish missing the
# `set -q …; or set -gx …` budget defaults: curl then got an empty --max-time
# and every live API call failed while all offline (mocked) suites stayed
# green. Assert the defaults exist in a FRESH process with the vars unset.
log_info "Demo-2 regression: STACK_API_TIMEOUT_* defaults initialized (fresh fish)..."
set budget_out (env -u STACK_API_TIMEOUT_LIGHT -u STACK_API_TIMEOUT_MUTATE \
    -u STACK_API_TIMEOUT_HEAVY -u STACK_DOCKER_TIMEOUT fish -N -c "
    source '$FISH_DIR/functions/__helpers.fish'
    echo \$STACK_API_TIMEOUT_LIGHT/\$STACK_API_TIMEOUT_MUTATE/\$STACK_API_TIMEOUT_HEAVY/\$STACK_DOCKER_TIMEOUT
" 2>/dev/null)
if test "$budget_out" = 10/20/30/5
    set passed (math $passed + 1)
    log_success "budget defaults initialize to 10/20/30/5 (got: $budget_out)"
else
    set failed (math $failed + 1)
    log_error "budget defaults wrong (got: '$budget_out', want 10/20/30/5)"
end

# --- Completions: generated file parses, registers both spellings, no drift ---
log_info "Completion checks (generated completions parse, register, are current)..."
set COMP_FILE "$FISH_DIR/completions/cave-completions.fish"
if not test -f "$COMP_FILE"
    set failed (math $failed + 1)
    log_error "completions file missing: $COMP_FILE"
else
    if fish -n "$COMP_FILE" >/dev/null 2>&1
        set passed (math $passed + 1)
        log_success "completions file parses (fish -n)"
    else
        set failed (math $failed + 1)
        log_error "completions file fails to parse"
    end
    set reg_cave (grep -oE '\bcave-[a-z0-9-]+' "$COMP_FILE" | sort -u | wc -l | string trim)
    set reg_stack (grep -oE '\bstack-[a-z0-9-]+' "$COMP_FILE" | sort -u | wc -l | string trim)
    if test "$reg_cave" -ge 128; and test "$reg_stack" -ge 128
        set passed (math $passed + 1)
        log_success "completions register $reg_cave cave-* + $reg_stack stack-* spellings"
    else
        set failed (math $failed + 1)
        log_error "completion registration incomplete (cave=$reg_cave stack=$reg_stack)"
    end
end

log_info "completion drift check (gen-fish-completions.sh --check)..."
if bash "$FISH_DIR/scripts/gen-fish-completions.sh" --check >/dev/null 2>&1
    set passed (math $passed + 1)
    log_success "fish completions are current (no drift)"
else
    set failed (math $failed + 1)
    log_error "fish completions are out of date — run gen-fish-completions.sh"
end

# --- Demo-2 regression: the generated completions file must LIVE-SOURCE clean ---
# fish -n only proves syntax; a bad `complete` flag (e.g. the bash-ism `-o` the
# generator once emitted) errors at source time on every rule while fish -n
# still passes. Source it in a throwaway fish and require silence.
log_info "Demo-2 regression: completions live-source clean (fish, stderr empty)..."
set live_src_err (fish -N -c "source '$FISH_DIR/completions/cave-completions.fish'" 2>&1 >/dev/null)
if test $status -eq 0; and test -z "$live_src_err"
    set passed (math $passed + 1)
    log_success "completions file sources with no errors in a live fish"
else
    set failed (math $failed + 1)
    log_error "completions file errors when sourced live"
    echo "$live_src_err" | head -3 | sed 's/^/         /'
end

log_info "alias drift check (gen-fish-aliases.sh --check)..."
if bash "$FISH_DIR/scripts/gen-fish-aliases.sh" --check >/dev/null 2>&1
    set passed (math $passed + 1)
    log_success "fish aliases are current (no drift)"
else
    set failed (math $failed + 1)
    log_error "fish aliases are out of date — run gen-fish-aliases.sh"
end

# --- Parity tier: bash and fish ports are byte-identical on shared commands ---
# The Demo-2 contract: the same command run in bash and fish produces the same
# bytes. Every parity pair sources its own loader and diffs stdout/stderr.
log_info "parity: cave-version + cave-help byte-identical to the bash port..."
function run_both --argument-names script
    set -l bash_out (bash -c "
        unset CAVE_SCRIPTS_DIR
        STACK_COLOR=false
        source '$BASH_DIR/cave-scripts.sh' >/dev/null 2>&1
        $script
    " 2>&1); set bash_rc $status
    set -l fish_out (env -u CAVE_SCRIPTS_DIR HOME="$TEST_HOME" fish -N -c "
        set -gx STACK_COLOR false
        source '$FISH_DIR/cave-scripts.fish' >/dev/null 2>&1
        $script
    " 2>&1); set fish_rc $status
    if test "$bash_rc" -eq "$fish_rc"; and test "$bash_out" = "$fish_out"
        set -g passed (math $passed + 1)
        log_success "parity: $script (rc=$bash_rc, byte-identical)"
    else
        set -g failed (math $failed + 1)
        log_error "parity: $script diverges (bash rc=$bash_rc vs fish rc=$fish_rc)"
        diff (echo "$bash_out" | psub) (echo "$fish_out" | psub) | head -6 | sed 's/^/         /'
    end
end
run_both "cave-version"
run_both "cave-help"

# --- Parity: cave-arr-missing-aired sonarr renderer (mock, both shells) ---
log_info "parity: missing-aired sonarr renderer (mock fixture, bash vs fish)..."
set mock_file (mktemp)
printf '%s' '{"records":[{"seriesId":42,"seasonNumber":3,"episodeNumber":7,"title":"The Test"},{"seriesId":7,"seasonNumber":1,"episodeNumber":2,"title":"Second"}],"totalRecords":3}' > "$mock_file"
set bash_out (SONARR_URL='http://127.0.0.1:1' SONARR_API_KEY='mock-key' STACK_COLOR=false bash -c '
    MOCK_FILE="$2"
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __stack_curl() { cat "$MOCK_FILE"; }
    "$3" sonarr 5
' _ "$BASH_DIR/cave-scripts.sh" "$mock_file" cave-arr-missing-aired 2>&1); set brc $status
set fish_out (SONARR_URL='http://127.0.0.1:1' SONARR_API_KEY='mock-key' STACK_COLOR=false \
    MOCK_FILE="$mock_file" fish -N -c '
    set -x mock_file "$MOCK_FILE"
    source "$argv[1]" >/dev/null 2>&1
    function __stack_curl; cat $mock_file; end
    $argv[2] sonarr 5
' "$FISH_DIR/cave-scripts.fish" cave-arr-missing-aired 2>&1); set frc $status
rm -f "$mock_file"
set bash_out (printf '%s\n' $bash_out)
set fish_out (printf '%s\n' $fish_out)
set parity_ok (test "$brc" -eq "$frc"; and test "$bash_out" = "$fish_out"; and string match -q '*? S03E07 The Test*' -- "$fish_out"; and string match -q '*? S01E02 Second*' -- "$fish_out"; and string match -q '*... and 1 more*' -- "$fish_out"; and echo yes)
if test "$parity_ok" = yes
    set passed (math $passed + 1)
    log_success "parity: missing-aired sonarr renderer byte-identical + correct (rc=$brc)"
else
    set failed (math $failed + 1)
    log_error "parity: missing-aired sonarr renderer diverges (bash rc=$brc vs fish rc=$frc)"
    echo "--- fish output ---"
    echo "$fish_out" | tail -6 | sed 's/^/         /'
end

# --- Parity: cave-requests Seerr renderer (mock, both shells) ---
log_info "parity: cave-requests Seerr renderer (mock fixture, bash vs fish)..."
set seerr_counts_mock (mktemp)
set seerr_list_mock (mktemp)
printf '%s' '{"total":10,"movie":6,"tv":4,"pending":0,"approved":2,"declined":1,"failed":0,"processing":1,"available":0,"completed":6}' > "$seerr_counts_mock"
printf '%s' '{"pageInfo":{"pages":1,"pageSize":10,"results":6,"page":1},"results":['\
'{"id":1,"status":2,"type":"movie","media":{"title":null,"tmdbId":41264,"status":3},"requestedBy":{"plexUsername":"RequesterA"}},'\
'{"id":2,"status":2,"type":"movie","media":{"title":"Watchable Now","tmdbId":77,"status":5},"requestedBy":{"plexUsername":"RequesterD"}},'\
'{"id":3,"status":1,"type":"tv","media":{"title":null,"tvdbId":55,"status":2},"requestedBy":{"plexUsername":"RequesterF"}},'\
'{"id":4,"status":5,"type":"movie","media":{"title":"Closed And Available","tmdbId":99,"status":5},"requestedBy":{"plexUsername":"RequesterB"}},'\
'{"id":5,"status":3,"type":"movie","media":{"title":"Declined Flick","tmdbId":123,"status":3},"requestedBy":{"plexUsername":"RequesterE"}},'\
'{"id":6,"status":4,"type":"tv","media":{"title":"Failed Show","tmdbId":456,"status":3},"requestedBy":{"plexUsername":"RequesterG"}}]}' > "$seerr_list_mock"
set bash_out (SEERR_API_KEY='mock-key' STACK_COLOR=false bash -c '
    COUNTS="$2" LIST="$3"
    unset CAVE_SCRIPTS_DIR; source "$1" >/dev/null 2>&1
    __seerr_api() {
        case "$2" in
            *"request/count"*) cat "$COUNTS" ;;
            *) cat "$LIST" ;;
        esac
    }
    "$4" 10
' _ "$BASH_DIR/cave-scripts.sh" "$seerr_counts_mock" "$seerr_list_mock" cave-requests 2>&1); set brc $status
set fish_out (SEERR_API_KEY='mock-key' STACK_COLOR=false \
    COUNTS_FILE="$seerr_counts_mock" LIST_FILE="$seerr_list_mock" fish -N -c '
    set -x counts_file "$COUNTS_FILE"
    set -x list_file "$LIST_FILE"
    source "$argv[1]" >/dev/null 2>&1
    function __seerr_api
        if string match -q "*request/count*" -- "$argv[2]"
            cat $counts_file
        else
            cat $list_file
        end
    end
    $argv[2] 10
' "$FISH_DIR/cave-scripts.fish" cave-requests 2>&1); set frc $status
rm -f "$seerr_counts_mock" "$seerr_list_mock"
set bash_out (printf '%s\n' $bash_out)
set fish_out (printf '%s\n' $fish_out)
set parity_ok (test "$brc" -eq "$frc"; and test "$bash_out" = "$fish_out"; and string match -q '*total=10 pending=0 approved=2 declined=1 failed=0*' -- "$fish_out"; and string match -q '*[movie] tmdb:41264 - by RequesterA (processing)*' -- "$fish_out"; and not string match -q '*Closed And Available*' -- "$fish_out"; and echo yes)
if test "$parity_ok" = yes
    set passed (math $passed + 1)
    log_success "parity: requests renderer byte-identical + correct (rc=$brc)"
else
    set failed (math $failed + 1)
    log_error "parity: requests renderer diverges (bash rc=$brc vs fish rc=$frc)"
    echo "--- fish output ---"
    echo "$fish_out" | tail -6 | sed 's/^/         /'
end

# --- Unit: cave-arrival-notify --help prints usage (fish, offline) ---
log_info "unit: cave-arrival-notify --help prints usage (fish)..."
set arr_help_out (fish -N -c '
    source "$argv[1]" >/dev/null 2>&1
    cave-arrival-notify --help
' "$FISH_DIR/cave-scripts.fish" 2>&1); set rc $status
if test "$rc" -eq 0; and string match -q '*Usage: cave-arrival-notify*' -- "$arr_help_out"
    set passed (math $passed + 1)
    log_success "unit: arrival-notify --help prints usage (exit 0)"
else
    set failed (math $failed + 1)
    log_error "unit: arrival-notify --help unexpected (rc=$rc): [$arr_help_out]"
end

# --- Unit: cave-activity-feed refuses >1 arg (fish, offline) ---
log_info "unit: cave-activity-feed refuses extra args (fish)..."
set feed_usage_out (fish -N -c '
    source "$argv[1]" >/dev/null 2>&1
    cave-activity-feed 5 bogus
' "$FISH_DIR/cave-scripts.fish" 2>&1); set rc $status
if test "$rc" -eq 1; and string match -q '*Usage: cave-activity-feed*' -- "$feed_usage_out"
    set passed (math $passed + 1)
    log_success "unit: activity-feed refuses >1 arg with usage (exit 1)"
else
    set failed (math $failed + 1)
    log_error "unit: activity-feed usage unexpected (rc=$rc): [$feed_usage_out]"
end

# --- Unit: stale arr key/URL warning (fish, offline) ---
log_info "unit: stale arr key warning fires on mismatch, silent on match (fish)..."
set stale_tmp (mktemp -d)
printf 'SONARR_API_KEY=real-key\nRADARR_URL=http://real:7878\n' > "$stale_tmp/.env"
set stale_out (SONARR_API_KEY='stale-key' RADARR_URL='http://real:7878' \
    BEARCAVE_REPO_DIR="$stale_tmp" STACK_COLOR=false fish -c '
    source "$argv[1]" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' "$FISH_DIR/cave-scripts.fish" 2>&1); set rc $status
set match_out (SONARR_API_KEY='real-key' RADARR_URL='http://real:7878' \
    BEARCAVE_REPO_DIR="$stale_tmp" STACK_COLOR=false fish -c '
    source "$argv[1]" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' "$FISH_DIR/cave-scripts.fish" 2>&1)
set noenv_out (SONARR_API_KEY='stale-key' BEARCAVE_REPO_DIR=(mktemp -d) \
    STACK_COLOR=false fish -c '
    source "$argv[1]" >/dev/null 2>&1
    __bearcave_warn_stale_keys
' "$FISH_DIR/cave-scripts.fish" 2>&1)
rm -rf "$stale_tmp"
if string match -q '*SONARR_API_KEY*' -- "$stale_out" \
    and not string match -q '*RADARR_URL*' -- "$stale_out" \
    and test -z "$match_out"; and test -z "$noenv_out"
    set passed (math $passed + 1)
    log_success "unit: stale arr key warning fires on mismatch, silent on match (fish)"
else
    set failed (math $failed + 1)
    log_error "unit: stale arr key warning unexpected (stale=[$stale_out] match=[$match_out] noenv=[$noenv_out])"
end

# --- Guard tier: mutating/arg-requiring commands refuse cleanly with no args ---
log_info "Guard tier (no-args invocations must print usage and exit cleanly)..."
function run_guard --argument-names name
    set -l output (timeout 20 fish -N -c "
        source '$FISH_DIR/cave-scripts.fish' >/dev/null 2>&1
        $name
    " </dev/null 2>&1); set -l rc $status
    if test "$rc" -le 1; and test -n "$output"
        set -g passed (math $passed + 1)
        log_success "guard: $name (exit $rc, refused with output)"
    else
        set -g failed (math $failed + 1)
        log_error "guard: $name (exit $rc, "(test -n "$output"; and echo "had output"; or echo "no output")")"
        echo "$output" | tail -3 | sed 's/^/         /'
    end
end

for cmd in \
    cave-arr-backlog cave-arr-blocklist cave-arr-clear-blocklist \
    cave-arr-import cave-arr-import-candidates cave-arr-logs \
    cave-arr-missing-aired cave-arr-queue-errors cave-arr-recently-added \
    cave-arr-toggle-search cave-container cave-cutoff-unmet cave-disk-reclaim \
    cave-import-lists cave-loop-candidates cave-loop-exclude cave-loop-unmonitor \
    cave-radarr-prune cave-sonarr-prune cave-worktree \
    cave-btrfs-snapshot cave-btrfs-subvol cave-btrfs-scrub \
    cave-btrfs-balance cave-btrfs-snapper
    if contains "$cmd" $CAVE_CMDS
        run_guard "$cmd"
    end
end

# cave-restart-all prompts for confirmation; with no stdin it must decline.
if contains "cave-restart-all" $CAVE_CMDS
    run_guard cave-restart-all
end

# --- Summary ---
echo ""
echo "=========================================="
if test "$failed" -eq 0
    echo "  ALL PASSED ($passed checks)"
    echo "=========================================="
    exit 0
else
    echo "  FAILED: $failed checks failed ($passed passed)"
    echo "=========================================="
    exit 1
end
