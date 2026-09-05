# ============================================================================
# cave-arrivals — request->arrival notifier + media activity feed
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

# cave-arrival-notify — one Discord ping per Seerr request that arrives
function cave-arrival-notify --description 'ping Discord once per Seerr request whose media arrives'
# complete: --dry-run|--no-refresh|--json
    if test (count $argv) -gt 0; and test "$argv[1]" = "-h" -o "$argv[1]" = "--help"
        echo "Usage: cave-arrival-notify [--dry-run] [--no-refresh] [--json]" >&2
        echo "Ping Discord once per Seerr request whose media actually arrives." >&2
        echo "  --dry-run     detect arrivals without sending or refreshing" >&2
        echo "  --no-refresh  skip the Plex section refresh on arrival" >&2
        echo "  --json        machine-readable report" >&2
        return 0
    end
    set -l repo "$BEARCAVE_REPO_DIR"
    python3 "$repo/scripts/arrival_notifier.py" $argv
end

# cave-activity-feed [limit] — poll *arr history, update the feed, print
function cave-activity-feed --description 'poll *arr history, update the feed, print latest entries'
# complete: <limit>
    if test (count $argv) -gt 1
        echo "Usage: cave-activity-feed [limit]" >&2
        return 1
    end
    set -l limit "$argv[1]"
    test -n "$limit"; or set limit 10
    set -l repo "$BEARCAVE_REPO_DIR"
    python3 "$repo/scripts/activity_feed.py" --print "$limit"
end
