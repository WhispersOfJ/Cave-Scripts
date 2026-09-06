#!/usr/bin/env bash
# ============================================================================
# tests/live/test_live_parity.sh — LIVE three-shell parity regression harness
# ============================================================================
# Re-runs the Demo 2 gates against the real stack: the same read-only command
# executed by the bash, zsh, and fish ports must produce BYTE-IDENTICAL
# output, and the three tab completers must offer identical candidate sets.
#
# Why this exists: the offline suites mock __stack_curl and only statically
# inspect completion files, so they cannot see live-API or live-source
# defects. Demo 2 (2026-09-05) caught three such defects this harness now
# pins:
#   1. fish __helpers.fish must default STACK_API_TIMEOUT_* (empty --max-time
#      broke every live curl call).
#   2. zsh must never assign `path` as a local (PATH-tied array clobber →
#      "command not found: curl" mid-call-chain). Static gate lives in the
#      zsh offline suite; this harness re-verifies it at call time.
#   3. fish completions must live-source clean (invalid `complete` flags
#      errored on every line). Offline gate: tests/fish suite sources the
#      generated file.
#
# D11/D13 split: the offline per-shell suites are the CI merge gate; this
# harness is the live tier and needs the stack reachable. It self-skips
# (exit 0) when Plex/Radarr are not answering unless --force is given.
#
# Usage:
#   tests/live/test_live_parity.sh              # run if stack is up, else skip
#   tests/live/test_live_parity.sh --force      # run even if preflight fails
#   tests/live/test_live_parity.sh --list       # print the gate list
# ============================================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[SKIP]${NC} $1"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $1"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASH_LOADER="$REPO_DIR/bash/cave-scripts.sh"
ZSH_LOADER="$REPO_DIR/zsh/cave-scripts.zsh"
FISH_LOADER="$REPO_DIR/fish/cave-scripts.fish"
ZSH_COMPDEF="$REPO_DIR/zsh/completions/_cave-cmd"
FISH_COMPLETIONS="$REPO_DIR/fish/completions/cave-completions.fish"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1
if [ "${1:-}" = "--list" ]; then
    echo "live parity gates:"
    echo "  preflight        stack reachable (plex identity + radarr ping)"
    echo "  parity-help      cave-help        byte-identical x bash/zsh/fish"
    echo "  parity-version   cave-version     byte-identical x bash/zsh/fish"
    echo "  parity-plexlib   cave-plex-libraries        byte-identical x3"
    echo "  parity-arrrec    cave-arr-recently-added    byte-identical x3"
    echo "  parity-alias     stack-arr-backlog radarr     byte-identical x3"
    echo "  completion-plex  cave-plex @arg1  (butler actions)"
    echo "  completion-arr   cave-arr  @arg1  (arr apps)"
    echo "  completion-ctr   cave-container @arg1 (live docker containers)"
    exit 0
fi

for f in "$BASH_LOADER" "$ZSH_LOADER" "$FISH_LOADER" "$ZSH_COMPDEF" "$FISH_COMPLETIONS"; do
    if [ ! -f "$f" ]; then
        log_error "missing $f"
        exit 1
    fi
done
for sh in bash zsh fish; do
    command -v "$sh" >/dev/null 2>&1 || { log_error "$sh not on PATH"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Runners: each sources its own loader in a clean env (the loaders resolve the
# stack .env themselves via BEARCAVE_REPO_DIR — no credential injection here).
# STACK_COLOR=false pins the no-color path; timeouts are unset so the ports'
# own defaults rule (a wrong default is exactly what this harness must catch).
# ---------------------------------------------------------------------------
run_bash() { # $1 = snippet
    bash -c "
        unset CAVE_SCRIPTS_DIR STACK_API_TIMEOUT_LIGHT STACK_API_TIMEOUT_MUTATE STACK_API_TIMEOUT_HEAVY STACK_DOCKER_TIMEOUT
        export STACK_COLOR=false
        source '$BASH_LOADER' >/dev/null 2>&1
        $1
    " 2>&1
}
run_zsh() {
    zsh -f -c "
        unset CAVE_SCRIPTS_DIR STACK_API_TIMEOUT_LIGHT STACK_API_TIMEOUT_MUTATE STACK_API_TIMEOUT_HEAVY STACK_DOCKER_TIMEOUT
        export STACK_COLOR=false
        source '$ZSH_LOADER' >/dev/null 2>&1
        $1
    " 2>&1
}
run_fish() {
    env -u CAVE_SCRIPTS_DIR -u STACK_API_TIMEOUT_LIGHT -u STACK_API_TIMEOUT_MUTATE \
        -u STACK_API_TIMEOUT_HEAVY -u STACK_DOCKER_TIMEOUT fish --no-config -N -c "
        set -e STACK_API_TIMEOUT_LIGHT STACK_API_TIMEOUT_MUTATE STACK_API_TIMEOUT_HEAVY STACK_DOCKER_TIMEOUT
        set -gx STACK_COLOR false
        source '$FISH_LOADER' >/dev/null 2>&1
        $1
    " 2>&1
}

# parity <gate-name> <command...> — compare the three outputs byte for byte.
parity() {
    local gate="$1"; shift
    local snippet="$*"
    run_bash  "$snippet" > "$WORK/$gate.bash"
    run_zsh   "$snippet" > "$WORK/$gate.zsh"
    run_fish  "$snippet" > "$WORK/$gate.fish"
    local b z f
    b=$(sha256sum "$WORK/$gate.bash" | cut -d' ' -f1)
    z=$(sha256sum "$WORK/$gate.zsh" | cut -d' ' -f1)
    f=$(sha256sum "$WORK/$gate.fish" | cut -d' ' -f1)
    if [ "$b" = "$z" ] && [ "$b" = "$f" ]; then
        log_success "$gate: byte-identical (sha256 ${b:0:12}…)"
        return 0
    fi
    log_error "$gate: outputs diverge (bash ${b:0:12}… zsh ${z:0:12}… fish ${f:0:12}…)"
    for shell in bash zsh fish; do
        echo "  --- $shell ---"
        head -6 "$WORK/$gate.$shell" | sed 's/^/  /'
    done
    return 1
}

# completion <gate-name> <function> <pos> — identical candidate sets x3.
completion() {
    local gate="$1" fn="$2" pos="$3"
    bash -c "
        source '$BASH_LOADER' >/dev/null 2>&1
        COMP_WORDS=('$fn' ''); COMP_CWORD=1; __stack_complete
        printf '%s\n' \"\${COMPREPLY[@]}\" | sort
    " > "$WORK/$gate.bash" 2>/dev/null
    zsh -f -c "
        source '$ZSH_COMPDEF'
        words=('$fn' ''); CURRENT=2
        cand=()
        compadd() { for a in \"\$@\"; do [ \"\$a\" = -- ] && continue; cand+=(\"\$a\"); done }
        _cave-cmd >/dev/null 2>&1
        printf '%s\n' \$cand | sort
    " > "$WORK/$gate.zsh" 2>/dev/null
    fish --no-config -N -c "
        source '$FISH_COMPLETIONS'
        __cave_complete $fn $pos | sort
    " > "$WORK/$gate.fish" 2>/dev/null
    if diff -q "$WORK/$gate.bash" "$WORK/$gate.zsh" >/dev/null 2>&1 \
       && diff -q "$WORK/$gate.bash" "$WORK/$gate.fish" >/dev/null 2>&1; then
        log_success "$gate: identical candidates ($(wc -l < "$WORK/$gate.bash") entries)"
        return 0
    fi
    log_error "$gate: candidate sets diverge"
    echo "  bash↔zsh:"; diff "$WORK/$gate.bash" "$WORK/$gate.zsh" | head -6 | sed 's/^/  /'
    echo "  bash↔fish:"; diff "$WORK/$gate.bash" "$WORK/$gate.fish" | head -6 | sed 's/^/  /'
    return 1
}

echo ""
echo "=========================================="
echo "  Cave-Scripts LIVE Three-Shell Parity"
echo "=========================================="
echo ""

# --- Preflight: stack reachable? -------------------------------------------
log_info "preflight: probing stack (plex identity, radarr ping)..."
plex_up=0; radarr_up=0
curl -sf --max-time 5 http://localhost:32400/identity >/dev/null 2>&1 && plex_up=1
curl -sf --max-time 5 http://localhost:7878/ping     >/dev/null 2>&1 && radarr_up=1
if [ "$plex_up" -ne 1 ] || [ "$radarr_up" -ne 1 ]; then
    if [ "$FORCE" -eq 1 ]; then
        log_warning "preflight failed (--force): plex=$plex_up radarr=$radarr_up — running anyway"
    else
        log_warning "stack not reachable (plex=$plex_up radarr=$radarr_up) — skipping live tier (use --force to override)"
        exit 0
    fi
else
    log_success "preflight: stack reachable"
fi

passed=0; failed=0

# --- Demo 2 regression gates ------------------------------------------------
# 1+2. The deterministic pair (also guards the zsh path-clobber call-time
# regression: these run __arr_api/__stack_curl for real in every shell).
if parity parity-help    'cave-help';    then passed=$((passed+1)); else failed=$((failed+1)); fi
if parity parity-version 'cave-version'; then passed=$((passed+1)); else failed=$((failed+1)); fi

# 3. Live Plex API through __plex_api (caught the fish budget-default defect).
if parity parity-plexlib 'cave-plex-libraries'; then passed=$((passed+1)); else failed=$((failed+1)); fi

# 4. Live Radarr API through __arr_api with a renderer.
if parity parity-arrrec 'cave-arr-recently-added radarr 5'; then passed=$((passed+1)); else failed=$((failed+1)); fi

# 5. Alias layer forwards live: stack-* ≡ cave-* (bash-driven call).
if parity parity-alias 'stack-arr-backlog radarr'; then passed=$((passed+1)); else failed=$((failed+1)); fi

# 6-8. Tab completion: static groups and the dynamic docker container source.
if completion completion-plex 'cave-plex' 0;       then passed=$((passed+1)); else failed=$((failed+1)); fi
if completion completion-arr  'cave-arr' 0;        then passed=$((passed+1)); else failed=$((failed+1)); fi
if completion completion-ctr  'cave-container' 0;  then passed=$((passed+1)); else failed=$((failed+1)); fi

echo ""
echo "=========================================="
if [ "$failed" -eq 0 ]; then
    echo "  LIVE PARITY: ALL PASSED ($passed gates)"
else
    echo "  LIVE PARITY: $failed FAILED, $passed passed"
fi
echo "=========================================="
[ "$failed" -eq 0 ]
