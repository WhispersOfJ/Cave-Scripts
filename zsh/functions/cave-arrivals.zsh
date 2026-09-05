# shellcheck shell=bash disable=SC2034
# ============================================================================
# cave-arrivals.sh — request->arrival notifier + media activity feed
# ============================================================================
# desc: arrival notifier, activity feed
# ============================================================================
# TODO.md #7 + #8. Both are thin, host-runnable jobs over the existing
# host-published APIs — no container, no listener, no state beyond JSON
# under .cache/ in the operational checkout. The python cores live in
# scripts/ (arrival_notifier.py, activity_feed.py) so the same logic runs
# from a shell AND from a user timer; these wrappers are the interactive
# surface.
#
# cave-arrival-notify [--dry-run|--no-refresh|--json]
#   Poll open Seerr requests; when the requested item actually lands (the
#   *arr app imported it), refresh Plex and send ONE Discord ping.
# cave-activity-feed [limit]
#   Poll the *arr History APIs, append imports/upgrades/deletions to the
#   JSONL feed, re-render feed.json + feed.xml, and print the latest
#   `limit` entries (default 10).
# ============================================================================

# __stack_repo_dir — repo root for the calling checkout (BEARCAVE_REPO_DIR
# is set by bearcave-bash.sh; fall back to a path walk from this file).
__stack_repo_dir() {
    if [ -n "${BEARCAVE_REPO_DIR:-}" ]; then
        echo "$BEARCAVE_REPO_DIR"
        return 0
    fi
    local self real
    self="${(%):-%x}"
    real="$(readlink -f "$self" 2>/dev/null || echo "$self")"
    echo "$(dirname "$(dirname "$(dirname "$(dirname "$real")")")")"
}

# cave-arrival-notify — one Discord ping per Seerr request that arrives
cave-arrival-notify() {
# complete: --dry-run|--no-refresh|--json
    if [ "$#" -gt 0 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
        echo "Usage: cave-arrival-notify [--dry-run] [--no-refresh] [--json]" >&2
        echo "Ping Discord once per Seerr request whose media actually arrives." >&2
        echo "  --dry-run     detect arrivals without sending or refreshing" >&2
        echo "  --no-refresh  skip the Plex section refresh on arrival" >&2
        echo "  --json        machine-readable report" >&2
        return 0
    fi
    local repo
    repo="$(__stack_repo_dir)"
    python3 "$repo/scripts/arrival_notifier.py" "$@"
}

# cave-activity-feed [limit] — poll *arr history, update the feed, print
cave-activity-feed() {
# complete: <limit>
    if [ "$#" -gt 1 ]; then
        echo "Usage: cave-activity-feed [limit]" >&2
        return 1
    fi
    local limit="${1:-10}"
    local repo
    repo="$(__stack_repo_dir)"
    python3 "$repo/scripts/activity_feed.py" --print "$limit"
}
