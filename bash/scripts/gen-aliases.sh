#!/usr/bin/env bash
# ============================================================================
# gen-aliases.sh — regenerate bash/_aliases.sh from spec/functions.yaml (D21)
# ============================================================================
# The stack-* alias layer is generated, never hand-edited: every registered
# function row with a stack-* source name gets a forwarder. Run after any
# registry change; --check verifies the committed file is current (CI gate).
#
# Usage:
#   bash/scripts/gen-aliases.sh            # write bash/_aliases.sh
#   bash/scripts/gen-aliases.sh --check    # verify (exit 1 if stale)
# ============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY="$REPO_DIR/spec/functions.yaml"
OUT_FILE="$REPO_DIR/bash/_aliases.sh"
CHECK=false
[ "${1:-}" = "--check" ] && CHECK=true

[ -f "$REGISTRY" ] || { echo "ERROR: $REGISTRY missing" >&2; exit 1; }

python3 - "$REGISTRY" <<'PY' > /tmp/gen-aliases.out
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
    '# _aliases.sh — permanent stack-* → cave-* alias layer (D21)',
    '# ============================================================================',
    '# Every stack-* command name forwards to its cave-* function so muscle',
    '# memory, cron lines, and docs keep working indefinitely. Generated from',
    '# spec/functions.yaml — regenerate with scripts/gen-aliases.sh (M2).',
    '# Aliases are real functions (not bash aliases) so they work in scripts,',
    '# completion, and non-interactive shells, and can be tested offline.',
    '#',
    '# Conformance: tests/bash/test_cave_scripts.sh asserts that every row in',
    '# functions.yaml has a cave-* function AND a stack-* forwarder here, and',
    '# that no stack-* forwarder lacks a cave-* target.',
    '# ============================================================================',
    '',
]
for src, dst in rows:
    lines.append(f'{src}() {{ {dst} "$@"; }}')
lines.append('')
sys.stdout.write('\n'.join(lines))
PY

if [ "$CHECK" = true ]; then
    if ! diff -q /tmp/gen-aliases.out "$OUT_FILE" >/dev/null 2>&1; then
        echo "FAIL: bash/_aliases.sh is out of date with spec/functions.yaml" >&2
        echo "  Regenerate: bash/scripts/gen-aliases.sh" >&2
        rm -f /tmp/gen-aliases.out
        exit 1
    fi
    echo "OK: bash/_aliases.sh is current."
else
    mv /tmp/gen-aliases.out "$OUT_FILE"
    echo "Wrote bash/_aliases.sh ($(grep -c '^stack-' "$OUT_FILE") forwarders)."
fi