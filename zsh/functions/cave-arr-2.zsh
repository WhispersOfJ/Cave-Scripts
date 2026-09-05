# ============================================================================
# cave-arr-2 — arr diagnostics (part 2)
# ============================================================================
# desc: arr missing, cutoff, import, logs commands
# ============================================================================

# cave-arr-import <radarr|sonarr> — trigger manual import of downloaded items
cave-arr-import() {
# complete: radarr|sonarr
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-arr-import <radarr|sonarr>" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local url key name
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    name="DownloadedMoviesScan"
    [ "$app" = sonarr ] && name="DownloadedEpisodesScan"

    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/command" -H "X-Api-Key: $key" \
        -H 'Content-Type: application/json' \
        -d "{\"name\": \"$name\"}" >/dev/null 2>&1; then
        fmt_success "$app: $name triggered."
    else
        fmt_error "Failed to trigger $name for $app."
        return 1
    fi
}

# cave-arr-import-all <radarr|sonarr> — trigger import on all movies/series
cave-arr-import-all() {
# complete: radarr|sonarr
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-arr-import-all <radarr|sonarr>" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local url key name
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    name="DownloadedMoviesScan"
    [ "$app" = sonarr ] && name="DownloadedEpisodesScan"

    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/command" -H "X-Api-Key: $key" \
        -H 'Content-Type: application/json' \
        -d "{\"name\": \"$name\"}" >/dev/null 2>&1; then
        fmt_success "$app: $name triggered."
    else
        fmt_error "Failed to trigger $name for $app."
        return 1
    fi
}

# cave-arr-import-candidates <radarr|sonarr> — items eligible for manual import
cave-arr-import-candidates() {
# complete: radarr|sonarr
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-arr-import-candidates <radarr|sonarr>" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local url key result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    fmt_heading "$app — Import Candidates"
    echo ""

    # Query queue for completed downloads awaiting import (same as fish version;
    # the bare /manualimport endpoint hangs Radarr when called without params)
    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/queue?pageSize=100&status=completed" -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach $app"
        return 1
    fi

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
}

# cave-arr-import-starvation <radarr|sonarr> — imported but not tracked/mapped
cave-arr-import-starvation() {
# complete: radarr|sonarr
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-arr-import-starvation <radarr|sonarr>" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    fmt_heading "$app — Import Starvation"
    echo ""
    fmt_warning "Import starvation check: see cave-arr-queue-errors and cave-arr-import-candidates."
}

# cave-arr-logs <radarr|sonarr> [lines] — recent log lines
cave-arr-logs() {
# complete: radarr|sonarr
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-arr-logs <radarr|sonarr> [lines]" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local lines="${2:-50}"
    local url key result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    fmt_heading "$app — Recent Logs ($lines lines)"
    echo ""

    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/log?pageSize=$lines&sortKey=time&sortDirection=descending" \
        -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach $app"
        return 1
    fi

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
}
