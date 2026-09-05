# ============================================================================
# cave-plex-updates — plex updates/analyze/empty-trash + queue autofix
# ============================================================================
# desc: plex updates, analyze, empty-trash, refresh-libraries, queue-autofix, sonarr-fix-episode-monitoring
# ============================================================================

# cave-plex-updates — check for Plex updates
cave-plex-updates() {
    local plex_url="${PLEX_URL:-http://localhost:32400}"
    local token="${PLEX_TOKEN:-}"

    fmt_heading "Plex — Updates"
    echo ""

    __stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/updater/check?X-Plex-Token=$token" 2>/dev/null \
        | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    updates = data.get('MediaContainer', {}).get('Metadata', [])
    if not updates:
        print('  No updates available.')
    for u in updates:
        print(f\"  {u.get('title', '?')} v{u.get('version', '?')}\")
except: pass
" 2>/dev/null
}

# cave-plex-analyze [library ...] — queue deep media analysis
cave-plex-analyze() {
    local lib="${1:-all}"
    local plex_url="${PLEX_URL:-http://localhost:32400}"
    local token="${PLEX_TOKEN:-}"

    fmt_heading "Plex — Analyze ($lib)"
    echo ""

    local ok=0 failed=0 key
    if [ "$lib" = all ]; then
        local sections
        sections="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
            | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", [])]' 2>/dev/null)"
        for key in $sections; do
            if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$plex_url/library/sections/$key/analyze?X-Plex-Token=$token" >/dev/null 2>&1; then
                ok=$((ok + 1))
            else
                failed=$((failed + 1))
            fi
        done
    else
        if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$plex_url/library/sections/$lib/analyze?X-Plex-Token=$token" >/dev/null 2>&1; then
            ok=$((ok + 1))
        else
            failed=$((failed + 1))
        fi
    fi
    if [ "$failed" -eq 0 ]; then
        fmt_success "Analysis queued for $ok section(s)."
    else
        fmt_error "Analysis queued for $ok section(s); $failed failed."
        return 1
    fi
}

# cave-plex-empty-trash — empty Plex trash for all libraries
cave-plex-empty-trash() {
    local plex_url="${PLEX_URL:-http://localhost:32400}"
    local token="${PLEX_TOKEN:-}"

    local sections failed=0 total=0 key
    sections="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
        | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", [])]' 2>/dev/null)"
    if [ -z "$sections" ]; then
        fmt_error "Cannot reach Plex or no libraries found."
        return 1
    fi
    for key in $sections; do
        total=$((total + 1))
        __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X PUT "$plex_url/library/sections/$key/emptyTrash?X-Plex-Token=$token" >/dev/null 2>&1 \
            || failed=$((failed + 1))
    done
    if [ "$failed" -eq 0 ]; then
        fmt_success "Trash emptied for $total section(s)."
    else
        fmt_error "Trash emptied for $((total - failed)) section(s); $failed failed."
        return 1
    fi
}

# cave-plex-refresh-libraries — refresh metadata for every library (butler)
cave-plex-refresh-libraries() {
    __plex_butler refresh-libraries
}

# cave-queue-autofix [-y|--yes] — auto-fix stuck queue items (blocklist+research)
cave-queue-autofix() {
# complete: -y|--yes
    local assume_yes=false a
    for a in "$@"; do
        case "$a" in
            -y|--yes) assume_yes=true ;;
        esac
    done
    if [ "$assume_yes" != true ]; then
        local confirm
        printf 'Auto-fix stuck queue items? This blocklists failed items. [y/N] '
        read -r confirm
        if [ "$confirm" != y ] && [ "$confirm" != Y ]; then
            echo "Cancelled."
            return 1
        fi
    fi

    fmt_heading "Queue Autofix"
    echo ""

    local app url key result
    for app in radarr sonarr; do
        url="$(__arr_api_url "$app")"
        key="$(__arr_api_key "$app")" || continue

        result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/queue?pageSize=100" -H "X-Api-Key: $key" 2>/dev/null)"
        if [ $? -ne 0 ]; then
            echo "  $app: unreachable"
            continue
        fi

        echo "$result" | APP="$app" URL="$url" KEY="$key" python3 -c "
import sys, json, subprocess, os
data = json.load(sys.stdin)
items = data.get('records', []) if isinstance(data, dict) else data
app = os.environ['APP']
url = os.environ['URL']
key = os.environ['KEY']
stuck = [q for q in items if q.get('trackedDownloadStatus') in ('error', 'failed', 'warning')]
if not stuck:
    print(f'  {app}: no stuck items')
else:
    for q in stuck:
        title = q.get('title', '?')
        qid = q.get('id')
        subprocess.run([
            'curl', '-sf', '--connect-timeout', '5', '--max-time', os.environ.get('STACK_API_TIMEOUT_MUTATE', '20'), '-X', 'POST',
            url + '/api/v3/blocklist',
            '-H', 'X-Api-Key: ' + key,
            '-H', 'Content-Type: application/json',
            '-d', json.dumps({'queueId': qid})
        ], capture_output=True)
        print(f'  {app}: blocklisted {title}')
    subprocess.run([
        'curl', '-sf', '--connect-timeout', '5', '--max-time', os.environ.get('STACK_API_TIMEOUT_MUTATE', '20'), '-X', 'POST',
        url + '/api/v3/command',
        '-H', 'X-Api-Key: ' + key,
        '-H', 'Content-Type: application/json',
        '-d', json.dumps({'name': 'MissingEpisodeSearch'})
    ], capture_output=True)
    print(f'  {app}: search triggered for {len(stuck)} items')
" 2>/dev/null
    done
}

# cave-sonarr-fix-episode-monitoring — trigger RefreshMonitoredDownloads on Sonarr
cave-sonarr-fix-episode-monitoring() {
    local url key
    url="$(__arr_api_url sonarr)"
    key="$(__arr_api_key sonarr)" || return 1
    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/command" \
        -H "X-Api-Key: $key" \
        -H "Content-Type: application/json" \
        -d '{"name": "RefreshMonitoredDownloads"}' >/dev/null 2>&1; then
        fmt_success "RefreshMonitoredDownloads triggered on sonarr."
    else
        fmt_error "Failed to trigger on sonarr."
    fi
}
