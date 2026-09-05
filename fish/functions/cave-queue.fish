# ============================================================================
# cave-queue — queue visibility commands
# ============================================================================
# desc: queue visibility commands (queues, history, stats, errors)
# ============================================================================

# cave-queue-status — Every app download queue with live speed/ETA
function cave-queue-status --description 'download queue across every arr app + nzbdav'
    fmt_heading "Queue Status"
    echo ""
    for app in radarr sonarr
        set -l url (__arr_api_url "$app")
        __arr_api_key "$app" >/dev/null; or continue
        set -l key (__arr_api_key "$app")
        set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/queue?pageSize=50" -H "X-Api-Key: $key" 2>/dev/null)
        if test $status -ne 0
            echo "  $app: unreachable"
            continue
        end
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
    end

    echo "  nzbdav:"
    __nzbdav_api GET queue 2>/dev/null | head -10
    echo ""
end

# cave-nzbdav-queue/history/stats now live in cave-nzbdav

# cave-arr-queue-errors <radarr|sonarr> [limit] — queue items in warning/error
function cave-arr-queue-errors --description 'queue items in warning/error state'
# complete: radarr|sonarr
    if test (count $argv) -lt 1
        echo "Usage: cave-arr-queue-errors <radarr|sonarr> [limit]" >&2
        return 1
    end
    set -l app (__stack_arr_app "$argv[1]")
    if test $status -ne 0
        echo "Invalid app: $argv[1]" >&2
        return 1
    end
    set -l limit "$argv[2]"
    test -n "$limit"; or set limit 10

    set -l url (__arr_api_url "$app")
    __arr_api_key "$app" >/dev/null; or return 1
    set -l key (__arr_api_key "$app")
    fmt_heading "$app — Queue Errors"
    echo ""

    set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/queue?page=1&pageSize=100" -H "X-Api-Key: $key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach $app"
        return 1
    end

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
end
