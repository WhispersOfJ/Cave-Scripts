# ============================================================================
# __host.fish — internal helpers for host-only (no-API) operations (fish port)
# ============================================================================
# Ported from services/host-tools/functions/__host_{containers,helper}.fish
# (M1 ledger section C, L2: renamed cave-sys-*). Internal — not user-facing.

# __host_containers — all docker container names (sorted), for completions.
function __host_containers --description 'all docker container names, sorted'
    docker ps -a --format '{{.Names}}' 2>/dev/null | sort
end

# __host_helper <cmd> — shared fragments for cave-sys-* commands.
function __host_helper --description 'shared host-only fragments: disk-free|journal-errors|journal-size'
    switch "$argv[1]"
        case disk-free
            df -h -x tmpfs -x devtmpfs -x overlay -x squashfs \
                --output=target,size,used,avail,pcent 2>/dev/null | tail -n +2
        case journal-errors
            journalctl -p err -b --no-pager -o short-iso 2>/dev/null | head -50
        case journal-size
            journalctl --disk-usage 2>/dev/null
        case '*'
            echo "Unknown host helper: $argv[1]" >&2
            return 1
    end
end
