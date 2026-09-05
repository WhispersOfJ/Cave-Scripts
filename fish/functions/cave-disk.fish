# ============================================================================
# cave-disk — disk usage commands + nzbdav history maintenance
# ============================================================================
# desc: disk config sizes, docker disk usage, nzbdav dedup/delete-failures
# ============================================================================

# cave-disk-config-sizes — per-app config directory sizes
function cave-disk-config-sizes --description 'per-app config directory sizes'
    fmt_heading "Config Directory Sizes"
    echo ""
    set -l base "$BEARCAVE_REPO_DIR"

    set -l found 0
    set -l dirs $base/config/*/ $base/data/*/
    for d in $dirs
        if test -d "$d"
            set -l size (du -sh "$d" 2>/dev/null | cut -f1)
            echo "  $d  $size"
            set found 1
        end
    end
    if test "$found" -eq 0
        echo "  No config/data directories found under $base"
    end

    # Docker's own footprint (needs root for the full picture)
    if test -d /var/lib/docker
        set -l size (sudo -n du -sh /var/lib/docker 2>/dev/null | cut -f1)
        if test -n "$size"
            echo "  /var/lib/docker  $size"
        end
    end
end

# cave-docker-disk-usage — Docker disk usage
function cave-docker-disk-usage --description 'Docker disk usage'
    fmt_heading "Docker Disk Usage"
    echo ""
    docker system df
end

# cave-disk-reclaim [-y|--yes] [--dry-run] [--aggressive] — reclaim Docker disk
# Prunes dangling volumes (explicit rm — docker volume prune skips labeled
# volumes), dangling images, build cache, and stopped containers. With
# --aggressive, also removes every image not referenced by docker-compose.yml
# (cache is re-pullable; this is the retired-stack/tooling accumulation class).
# Backed by scripts/reclaim_docker_disk.py. Safe to run nightly from cron.
function cave-disk-reclaim --description 'reclaim Docker disk (volumes/images/build-cache; --aggressive adds non-compose images)'
# complete: -y|--yes|--dry-run|--aggressive
# danger: true
    if test (count $argv) -eq 0
        echo "Usage: cave-disk-reclaim [-y|--yes] [--dry-run] [--aggressive]" >&2
        return 1
    end
    set -l assume_yes false
    set -l pargs
    for arg in $argv
        switch $arg
            case -y --yes
                set assume_yes true
            case --dry-run --aggressive
                set -a pargs "$arg"
            case -h --help
                echo "Usage: cave-disk-reclaim [-y|--yes] [--dry-run] [--aggressive]" >&2
                echo "Reclaim Docker disk: volumes/images/build-cache; --aggressive adds non-compose image removal." >&2
                return 0
            case '*'
                echo "Unknown option: $arg (usage: cave-disk-reclaim [-y|--yes] [--dry-run] [--aggressive])" >&2
                return 1
        end
    end

    set -l repo "$BEARCAVE_REPO_DIR"

    set -l need_confirm 1
    if test "$assume_yes" = true
        set need_confirm 0
    end
    if contains -- --dry-run $pargs
        set need_confirm 0
    end
    if test "$need_confirm" -eq 1
        printf 'Reclaim Docker disk space? [y/N] '
        set -l reply
        read -l reply
        switch $reply
            case y Y
            case '*'
                echo "Aborted."
                return 1
        end
    end

    cd "$repo"; or return 1
    python3 "$repo/scripts/reclaim_docker_disk.py" $pargs
end

# cave-nzbdav-dedup-check — duplicate entries in NzbDAV download history
function cave-nzbdav-dedup-check --description 'duplicate entries in NzbDAV download history'
    fmt_heading "NzbDAV Dedup Check"
    echo ""

    set -l result (__nzbdav_api GET history "limit=500" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach NzbDAV API"
        return 1
    end

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
end

# cave-nzbdav-delete-failures [-y|--yes] — delete failed downloads
function cave-nzbdav-delete-failures --description 'delete failed downloads from NzbDAV history (prompts unless -y)'
# complete: -y|--yes
    set -l assume_yes false
    for a in $argv
        switch $a
            case -y --yes
                set assume_yes true
        end
    end
    if test "$assume_yes" != true
        printf 'Delete all FAILED downloads from NzbDAV history? [y/N] '
        set -l confirm
        read -l confirm
        if test "$confirm" != y; and test "$confirm" != Y
            echo "Cancelled."
            return 1
        end
    end

    set -l result (__nzbdav_api GET history "limit=500" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach NzbDAV API"
        return 1
    end

    set -l failed_ids (echo "$result" | python3 -c "
import sys, json
try:
    slots = json.load(sys.stdin).get('history', {}).get('slots', [])
except Exception:
    sys.exit(1)
for s in slots:
    if s.get('status') == 'Failed':
        print(s.get('nzo_id', ''))
")

    if test (count $failed_ids) -eq 0
        fmt_success "No failed downloads in history."
        return 0
    end

    set -l deleted 0
    set -l errors 0
    for id in $failed_ids
        test -z "$id"; and continue
        if __nzbdav_api GET history "name=delete&value=$id" >/dev/null 2>&1
            set deleted (math "$deleted + 1")
        else
            set errors (math "$errors + 1")
        end
    end

    if test "$errors" -eq 0
        fmt_success "Deleted $deleted failed download(s)."
    else
        fmt_error "Deleted $deleted failed download(s); $errors delete(s) failed."
        return 1
    end
end
