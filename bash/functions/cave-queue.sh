# ============================================================================
# cave-queue.sh — queue visibility commands
# ============================================================================
# desc: queue visibility commands (queues, history, stats, errors)
# ============================================================================

# cave-queue-status — Every app download queue with live speed/ETA
cave-queue-status() {
    fmt_heading "Queue Status"
    echo ""
    local app url key result
    for app in radarr sonarr; do
        url="$(__arr_api_url "$app")"
        key="$(__arr_api_key "$app")" || continue
        result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/queue?pageSize=50" -H "X-Api-Key: $key" 2>/dev/null)"
        if [ $? -ne 0 ]; then
            echo "  $app: unreachable"
            continue
        fi
        echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('records', [])
print(f'  $app: {len(items)} item(s)')
for q in items[:10]:
    title = q.get('title', '?')
    status = q.get('status', '?')
    print(f'    {status}  {title}')
" 2>/dev/null
    done

    echo "  nzbdav:"
    __nzbdav_api GET queue 2>/dev/null | head -10
    echo ""
}

# cave-nzbdav-queue/history/stats now live in cave-nzbdav.sh

# cave-arr-queue-errors <radarr|sonarr> [limit] — queue items in warning/error
cave-arr-queue-errors() {
# complete: radarr|sonarr
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-arr-queue-errors <radarr|sonarr> [limit]" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local limit="${2:-10}"

    local url key result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    fmt_heading "$app — Queue Errors"
    echo ""

    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/queue?page=1&pageSize=100" -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach $app"
        return 1
    fi

    echo "$result" | LIMIT="$limit" python3 -c "
import sys, json, os
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f'  Error parsing response: {e}')
    sys.exit(1)
limit = int(os.environ['LIMIT'])
records = data.get('records', [])
errors = [q for q in records if q.get('status') in ('warning', 'error') or q.get('errorMessage')]
if not errors:
    print('  No queue errors.')
else:
    for q in errors[:limit]:
        title = q.get('title', '?')
        status = q.get('status', '?')
        msg = q.get('errorMessage') or q.get('statusMessages') or ''
        print(f'  [{status}] {title}')
        if msg and not isinstance(msg, (dict, list)):
            print(f'    {msg}')
    print('')
    print(f'  {len(errors)} item(s) in error/warning.')
"
}
