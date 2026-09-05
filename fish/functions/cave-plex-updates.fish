# ============================================================================
# cave-plex-updates — plex updates/analyze/empty-trash + queue autofix
# ============================================================================
# desc: plex updates, analyze, empty-trash, refresh-libraries, queue-autofix, sonarr-fix-episode-monitoring
# ============================================================================

# cave-plex-updates — check for Plex updates
function cave-plex-updates --description 'check for Plex updates'
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"

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
end

# cave-plex-analyze [library ...] — queue deep media analysis
function cave-plex-analyze --description 'queue deep media analysis (all libraries or one key)'
    set -l lib "$argv[1]"
    test -n "$lib"; or set lib all
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"

    fmt_heading "Plex — Analyze ($lib)"
    echo ""

    set -l ok 0
    set -l failed 0
    if test "$lib" = all
        set -l sections (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
            | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", [])]' 2>/dev/null)
        for key in $sections
            if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$plex_url/library/sections/$key/analyze?X-Plex-Token=$token" >/dev/null 2>&1
                set ok (math "$ok + 1")
            else
                set failed (math "$failed + 1")
            end
        end
    else
        if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$plex_url/library/sections/$lib/analyze?X-Plex-Token=$token" >/dev/null 2>&1
            set ok (math "$ok + 1")
        else
            set failed (math "$failed + 1")
        end
    end
    if test "$failed" -eq 0
        fmt_success "Analysis queued for $ok section(s)."
    else
        fmt_error "Analysis queued for $ok section(s); $failed failed."
        return 1
    end
end

# cave-plex-empty-trash — empty Plex trash for all libraries
function cave-plex-empty-trash --description 'empty Plex trash for all libraries'
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"

    set -l sections (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
        | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", [])]' 2>/dev/null)
    if test -z "$sections"
        fmt_error "Cannot reach Plex or no libraries found."
        return 1
    end
    set -l failed 0
    set -l total 0
    for key in $sections
        set total (math "$total + 1")
        __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X PUT "$plex_url/library/sections/$key/emptyTrash?X-Plex-Token=$token" >/dev/null 2>&1
        or set failed (math "$failed + 1")
    end
    if test "$failed" -eq 0
        fmt_success "Trash emptied for $total section(s)."
    else
        fmt_error "Trash emptied for "(math "$total - $failed")" section(s); $failed failed."
        return 1
    end
end

# cave-plex-refresh-libraries — refresh metadata for every library (butler)
function cave-plex-refresh-libraries --description 'refresh metadata for every library (butler)'
    __plex_butler refresh-libraries
end

# cave-queue-autofix [-y|--yes] — auto-fix stuck queue items (blocklist+research)
function cave-queue-autofix --description 'auto-fix stuck queue items (blocklist + search)'
# complete: -y|--yes
    set -l assume_yes false
    for a in $argv
        switch $a
            case -y --yes
                set assume_yes true
        end
    end
    if test "$assume_yes" != true
        printf 'Auto-fix stuck queue items? This blocklists failed items. [y/N] '
        set -l confirm
        read -l confirm
        if test "$confirm" != y; and test "$confirm" != Y
            echo "Cancelled."
            return 1
        end
    end

    fmt_heading "Queue Autofix"
    echo ""

    for app in radarr sonarr
        set -l url (__arr_api_url "$app")
        __arr_api_key "$app" >/dev/null; or continue
        set -l key (__arr_api_key "$app")

        set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/queue?pageSize=100" -H "X-Api-Key: $key" 2>/dev/null)
        if test $status -ne 0
            echo "  $app: unreachable"
            continue
        end

        echo "$result" | APP="$app" URL="$url" KEY="$key" STACK_API_TIMEOUT_MUTATE="$STACK_API_TIMEOUT_MUTATE" python3 -c "
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
    end
end

# cave-sonarr-fix-episode-monitoring — trigger RefreshMonitoredDownloads on Sonarr
function cave-sonarr-fix-episode-monitoring --description 'trigger RefreshMonitoredDownloads on Sonarr'
    set -l url (__arr_api_url sonarr)
    set -l key (__arr_api_key sonarr); or return 1
    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/command" \
        -H "X-Api-Key: $key" \
        -H "Content-Type: application/json" \
        -d '{"name": "RefreshMonitoredDownloads"}' >/dev/null 2>&1
        fmt_success "RefreshMonitoredDownloads triggered on sonarr."
    else
        fmt_error "Failed to trigger on sonarr."
    end
end
