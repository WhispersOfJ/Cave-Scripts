# ============================================================================
# cave-disk — disk usage commands + nzbdav history maintenance
# ============================================================================
# desc: disk config sizes, docker disk usage, nzbdav dedup/delete-failures
# ============================================================================

# cave-disk-config-sizes — per-app config directory sizes
cave-disk-config-sizes() {
    fmt_heading "Config Directory Sizes"
    echo ""
    local base="$BEARCAVE_REPO_DIR"

    local found=0 d size
    for d in "$base"/config/*/ "$base"/data/*/; do
        if [ -d "$d" ]; then
            size="$(du -sh "$d" 2>/dev/null | cut -f1)"
            echo "  $d  $size"
            found=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        echo "  No config/data directories found under $base"
    fi

    # Docker's own footprint (needs root for the full picture)
    if [ -d /var/lib/docker ]; then
        size="$(sudo -n du -sh /var/lib/docker 2>/dev/null | cut -f1)"
        if [ -n "$size" ]; then
            echo "  /var/lib/docker  $size"
        fi
    fi
}

# cave-docker-disk-usage — Docker disk usage
cave-docker-disk-usage() {
    fmt_heading "Docker Disk Usage"
    echo ""
    docker system df
}

# cave-disk-reclaim [-y|--yes] [--dry-run] [--aggressive] — reclaim Docker disk
# Prunes dangling volumes (explicit rm — docker volume prune skips labeled
# volumes), dangling images, build cache, and stopped containers. With
# --aggressive, also removes every image not referenced by docker-compose.yml
# (cache is re-pullable; this is the retired-stack/tooling accumulation class).
# Backed by scripts/reclaim_docker_disk.py. Safe to run nightly from cron.
cave-disk-reclaim() {
# complete: -y|--yes|--dry-run|--aggressive
# danger: true
    if [ "$#" -eq 0 ]; then
        echo "Usage: cave-disk-reclaim [-y|--yes] [--dry-run] [--aggressive]" >&2
        return 1
    fi
    local assume_yes=false
    local -a pargs=()
    for arg in "$@"; do
        case "$arg" in
            -y|--yes) assume_yes=true ;;
            --dry-run|--aggressive) pargs+=("$arg") ;;
            -h|--help)
                echo "Usage: cave-disk-reclaim [-y|--yes] [--dry-run] [--aggressive]" >&2
                echo "Reclaim Docker disk: volumes/images/build-cache; --aggressive adds non-compose image removal." >&2
                return 0
                ;;
            *)
                echo "Unknown option: $arg (usage: cave-disk-reclaim [-y|--yes] [--dry-run] [--aggressive])" >&2
                return 1
                ;;
        esac
    done

    local repo="${BEARCAVE_REPO_DIR:-}"
    if [ -z "$repo" ]; then
        local self="${(%):-%x}"
        local real
        real="$(readlink -f "$self" 2>/dev/null || echo "$self")"
        repo="$(dirname "$(dirname "$(dirname "$(dirname "$real")")")")"
    fi

    if [ "$assume_yes" != true ] && ! printf '%s' "${pargs[*]}" | grep -q -- '--dry-run'; then
        printf 'Reclaim Docker disk space? [y/N] '
        local reply
        read -r reply
        case "$reply" in
            y|Y) ;;
            *) echo "Aborted."; return 1 ;;
        esac
    fi

    cd "$repo" || return 1
    python3 "$repo/scripts/reclaim_docker_disk.py" "${pargs[@]}"
}

# cave-nzbdav-dedup-check — duplicate entries in NzbDAV download history
cave-nzbdav-dedup-check() {
    fmt_heading "NzbDAV Dedup Check"
    echo ""

    local result
    result="$(__nzbdav_api GET history "limit=500" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach NzbDAV API"
        return 1
    fi

    echo "$result" | python3 -c "
import sys, json
from collections import Counter
try:
    slots = json.load(sys.stdin).get('history', {}).get('slots', [])
except Exception as e:
    print(f'  Error parsing history: {e}')
    sys.exit(1)

names = Counter(s.get('name') or s.get('nzb_name', '?') for s in slots)
dupes = [(n, c) for n, c in names.most_common() if c > 1]
if not dupes:
    print('  No duplicate downloads in recent history.')
else:
    total_extra = 0
    for name, count in dupes:
        print(f'  [{count}x] {name}')
        total_extra += count - 1
    print(f'\n  {len(dupes)} title(s) duplicated ({total_extra} redundant grab(s)).')
"
}

# cave-nzbdav-delete-failures [-y|--yes] — delete failed downloads
cave-nzbdav-delete-failures() {
# complete: -y|--yes
    local assume_yes=false
    local a
    for a in "$@"; do
        case "$a" in
            -y|--yes) assume_yes=true ;;
        esac
    done
    if [ "$assume_yes" != true ]; then
        local confirm
        printf 'Delete all FAILED downloads from NzbDAV history? [y/N] '
        read -r confirm
        if [ "$confirm" != y ] && [ "$confirm" != Y ]; then
            echo "Cancelled."
            return 1
        fi
    fi

    local result
    result="$(__nzbdav_api GET history "limit=500" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach NzbDAV API"
        return 1
    fi

    local failed_ids
    failed_ids="$(echo "$result" | python3 -c "
import sys, json
try:
    slots = json.load(sys.stdin).get('history', {}).get('slots', [])
except Exception:
    sys.exit(1)
for s in slots:
    if s.get('status') == 'Failed':
        print(s.get('nzo_id', ''))
")"

    if [ -z "$failed_ids" ]; then
        fmt_success "No failed downloads in history."
        return 0
    fi

    local deleted=0 errors=0 id
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        if __nzbdav_api GET history "name=delete&value=$id" >/dev/null 2>&1; then
            deleted=$((deleted + 1))
        else
            errors=$((errors + 1))
        fi
    done <<< "$failed_ids"

    if [ "$errors" -eq 0 ]; then
        fmt_success "Deleted $deleted failed download(s)."
    else
        fmt_error "Deleted $deleted failed download(s); $errors delete(s) failed."
        return 1
    fi
}
