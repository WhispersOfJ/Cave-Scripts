#!/usr/bin/env bash
# ============================================================================
# gen-fish-aliases.sh — regenerate fish/_aliases.fish from spec/functions.yaml
# ============================================================================
# The stack-* alias layer is generated, never hand-edited: every registered
# function row gets a fish forwarder. Run after any registry change; --check
# verifies the committed file is current (CI gate). Same registry contract as
# bash/scripts/gen-aliases.sh (D21), fish function syntax (fish has no POSIX
# function bodies; `alias` would not forward arguments transparently enough
# for scripts, so real wrapper functions are generated).
#
# Usage:
#   fish/scripts/gen-fish-aliases.sh            # write fish/_aliases.fish
#   fish/scripts/gen-fish-aliases.sh --check    # verify (exit 1 if stale)
# ============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY="$REPO_DIR/spec/functions.yaml"
OUT_FILE="$REPO_DIR/fish/_aliases.fish"
CHECK=false
[ "${1:-}" = "--check" ] && CHECK=true

[ -f "$REGISTRY" ] || { echo "ERROR: $REGISTRY missing" >&2; exit 1; }

python3 - "$REGISTRY" <<'PY' > /tmp/gen-fish-aliases.out
import sys, yaml

reg = yaml.safe_load(open(sys.argv[1]))
rows = []
for f in reg['functions']:
    n = f['name']
    if f['family'] in ('de', 'backup', 'btrfs'):
        continue  # new families land in M3; no stack-* source yet
    if n.startswith('cave-sys-'):
        src = 'stack' + n[8:]  # cave-sys-X <- stack-X (host-tools source)
    else:
        src = 'stack' + n[4:]  # cave-X <- stack-X
    rows.append((src, n))
rows.sort()

lines = [
    '# ============================================================================',
    '# _aliases.fish — permanent stack-* → cave-* alias layer (D21)',
    '# ============================================================================',
    '# Every stack-* command name forwards to its cave-* function so muscle',
    '# memory, cron lines, and docs keep working indefinitely. Generated from',
    '# spec/functions.yaml — regenerate with fish/scripts/gen-fish-aliases.sh.',
    '# Aliases are real fish functions (not `alias`es) so they forward',
    '# arguments and work in scripts, completion, and non-interactive shells.',
    '#',
    '# Conformance: tests/fish/test_cave_scripts.fish asserts that every row',
    '# in functions.yaml has a stack-* forwarder here, and that no forwarder',
    '# lacks a cave-* target.',
    '# ============================================================================',
    '',
]
for src, dst in rows:
    lines.append(f'function {src}; {dst} $argv; end')
lines.append('')
sys.stdout.write('\n'.join(lines))
PY

if [ "$CHECK" = true ]; then
    if ! diff -q /tmp/gen-fish-aliases.out "$OUT_FILE" >/dev/null 2>&1; then
        echo "FAIL: fish/_aliases.fish is out of date with spec/functions.yaml" >&2
        echo "  Regenerate: fish/scripts/gen-fish-aliases.sh" >&2
        rm -f /tmp/gen-fish-aliases.out
        exit 1
    fi
    echo "OK: fish/_aliases.fish is current."
else
    mv /tmp/gen-fish-aliases.out "$OUT_FILE"
    echo "Wrote fish/_aliases.fish ($(grep -c '^function stack-' "$OUT_FILE") forwarders)."
fi
