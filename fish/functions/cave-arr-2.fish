# ============================================================================
# cave-arr-2 — arr diagnostics (part 2)
# ============================================================================
# desc: arr missing, cutoff, import, logs commands
# ============================================================================

# cave-arr-import <radarr|sonarr> — trigger manual import of downloaded items
function cave-arr-import --description 'trigger manual import of downloaded items'
# complete: radarr|sonarr
    if test (count $argv) -ne 1
        echo "Usage: cave-arr-import <radarr|sonarr>" >&2
        return 1
    end
    set -l app (__stack_arr_app "$argv[1]")
    if test $status -ne 0
        echo "Invalid app: $argv[1]" >&2
        return 1
    end
    set -l url (__arr_api_url "$app")
    set -l key (__arr_api_key "$app"); or return 1
    set -l name "DownloadedMoviesScan"
    test "$app" = sonarr; and set name "DownloadedEpisodesScan"

    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/command" -H "X-Api-Key: $key" \
        -H 'Content-Type: application/json' \
        -d "{\"name\": \"$name\"}" >/dev/null 2>&1
        fmt_success "$app: $name triggered."
    else
        fmt_error "Failed to trigger $name for $app."
        return 1
    end
end

# cave-arr-import-all <radarr|sonarr> — trigger import on all movies/series
function cave-arr-import-all --description 'trigger import scan across all movies/series'
# complete: radarr|sonarr
    if test (count $argv) -ne 1
        echo "Usage: cave-arr-import-all <radarr|sonarr>" >&2
        return 1
    end
    set -l app (__stack_arr_app "$argv[1]")
    if test $status -ne 0
        echo "Invalid app: $argv[1]" >&2
        return 1
    end
    set -l url (__arr_api_url "$app")
    set -l key (__arr_api_key "$app"); or return 1
    set -l name "DownloadedMoviesScan"
    test "$app" = sonarr; and set name "DownloadedEpisodesScan"

    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/command" -H "X-Api-Key: $key" \
        -H 'Content-Type: application/json' \
        -d "{\"name\": \"$name\"}" >/dev/null 2>&1
        fmt_success "$app: $name triggered."
    else
        fmt_error "Failed to trigger $name for $app."
        return 1
    end
end

# cave-arr-import-candidates <radarr|sonarr> — items eligible for manual import
function cave-arr-import-candidates --description 'queue items eligible for manual import'
# complete: radarr|sonarr
    if test (count $argv) -lt 1
        echo "Usage: cave-arr-import-candidates <radarr|sonarr>" >&2
        return 1
    end
    set -l app (__stack_arr_app "$argv[1]")
    if test $status -ne 0
        echo "Invalid app: $argv[1]" >&2
        return 1
    end
    set -l url (__arr_api_url "$app")
    __arr_api_key "$app" >/dev/null; or return 1
    set -l key (__arr_api_key "$app")
    fmt_heading "$app — Import Candidates"
    echo ""

    # Query queue for completed downloads awaiting import (same as fish version;
    # the bare /manualimport endpoint hangs Radarr when called without params)
    set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/queue?pageSize=100&status=completed" -H "X-Api-Key: $key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach $app"
        return 1
    end

    echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('records', []) if isinstance(data, dict) else data
if not items:
    print('  No import candidates.')
else:
    for i, t in enumerate(items, 1):
        title = t.get('title', '?')
        path = t.get('outputPath', t.get('sourcePath', '?'))
        print(f'  [{i}] {title}')
        print(f'       path: {path}')
" 2>/dev/null
end

# cave-arr-import-starvation <radarr|sonarr> — imported but not tracked/mapped
function cave-arr-import-starvation --description 'import-starvation pointer (see queue-errors / import-candidates)'
# complete: radarr|sonarr
    if test (count $argv) -lt 1
        echo "Usage: cave-arr-import-starvation <radarr|sonarr>" >&2
        return 1
    end
    set -l app (__stack_arr_app "$argv[1]")
    if test $status -ne 0
        echo "Invalid app: $argv[1]" >&2
        return 1
    end
    fmt_heading "$app — Import Starvation"
    echo ""
    fmt_warning "Import starvation check: see cave-arr-queue-errors and cave-arr-import-candidates."
end

# cave-arr-logs <radarr|sonarr> [lines] — recent log lines
function cave-arr-logs --description 'recent log lines for an arr app'
# complete: radarr|sonarr
    if test (count $argv) -lt 1
        echo "Usage: cave-arr-logs <radarr|sonarr> [lines]" >&2
        return 1
    end
    set -l app (__stack_arr_app "$argv[1]")
    if test $status -ne 0
        echo "Invalid app: $argv[1]" >&2
        return 1
    end
    set -l lines "$argv[2]"
    test -n "$lines"; or set lines 50
    set -l url (__arr_api_url "$app")
    __arr_api_key "$app" >/dev/null; or return 1
    set -l key (__arr_api_key "$app")
    fmt_heading "$app — Recent Logs ($lines lines)"
    echo ""

    set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/log?pageSize=$lines&sortKey=time&sortDirection=descending" \
        -H "X-Api-Key: $key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach $app"
        return 1
    end

    echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('records', [])
if not records:
    print('  No log records.')
else:
    for r in records:
        level = r.get('level', '?')
        msg = r.get('message', '')
        print(f'  [{level}] {msg}')
" 2>/dev/null
end
