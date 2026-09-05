# ============================================================================
# __host.sh — internal helpers for host-only (no-API) operations
# ============================================================================
# Ported from services/host-tools/functions/__host_{containers,helper}.fish
# (M1 ledger section C, L2: renamed cave-sys-*). Internal — not user-facing.

# __host_containers — all docker container names (sorted), for completions.
__host_containers() {
    docker ps -a --format '{{.Names}}' 2>/dev/null | sort
}

# __host_helper <cmd> — shared fragments for cave-sys-* commands.
__host_helper() {
    local cmd="${1:-}"
    case "$cmd" in
        disk-free)
            df -h -x tmpfs -x devtmpfs -x overlay -x squashfs \
                --output=target,size,used,avail,pcent 2>/dev/null | tail -n +2
            ;;
        journal-errors)
            journalctl -p err -b --no-pager -o short-iso 2>/dev/null | head -50
            ;;
        journal-size)
            journalctl --disk-usage 2>/dev/null
            ;;
        *)
            echo "Unknown host helper: $cmd" >&2
            return 1
            ;;
    esac
}