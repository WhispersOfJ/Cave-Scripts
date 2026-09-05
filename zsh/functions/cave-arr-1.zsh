# ============================================================================
# cave-arr-1 — arr diagnostics (part 1)
# ============================================================================
# desc: arr backlog, blocklist, recently-added, toggle-search commands
# ============================================================================

# cave-arr-backlog <radarr|sonarr> — internal command-queue backlog
cave-arr-backlog() {
# complete: radarr|sonarr
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-arr-backlog <radarr|sonarr>" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }

    local url key result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    fmt_heading "$app Command Queue"
    echo ""

    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/command?pageSize=50" -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach $app"
        return 1
    fi

    echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
cmds = data.get('records', [])
if not cmds:
    print('  Queue is empty.')
else:
    for c in cmds:
        print(f\"  {c.get('name', '?'):<30s} {c.get('status', '?'):<12s} {(c.get('queued', '') or '')[:19]}\")
" 2>/dev/null
}

# cave-arr-recently-added <radarr|sonarr> [limit]
cave-arr-recently-added() {
# complete: radarr|sonarr
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-arr-recently-added <radarr|sonarr> [limit]" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local limit="${2:-10}"

    local url key endpoint result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    endpoint="movie"
    [ "$app" = sonarr ] && endpoint="series"
    fmt_heading "$app — Recently Added"
    echo ""

    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/$endpoint?pageSize=$limit&sortKey=added&sortDirection=descending" \
        -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach $app"
        return 1
    fi

    echo "$result" | LIMIT="$limit" python3 -c "
import sys, json, os
data = json.load(sys.stdin)
if isinstance(data, list):
    items = data
else:
    items = data.get('movies', data.get('series', []))
for item in items[:int(os.environ['LIMIT'])]:
    title = item.get('title', '?')
    year = item.get('year', '?')
    has_file = '✓' if item.get('hasFile') else '✗'
    print(f'  [{has_file}] {title} ({year})')
" 2>/dev/null
}

# cave-arr-toggle-search <radarr|sonarr|all> <on|off>
cave-arr-toggle-search() {
# complete: radarr|sonarr|all on|off
    if [ "$#" -ne 2 ]; then
        echo "Usage: cave-arr-toggle-search <radarr|sonarr|all> <on|off>" >&2
        return 1
    fi
    case "$2" in
        on|off) ;;
        *) echo "Second argument must be on or off (got: $2)" >&2; return 1 ;;
    esac

    local apps
    if [ "$1" = all ]; then
        apps="radarr sonarr"
    else
        apps="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    fi

    local app url key count
    for app in $apps; do
        url="$(__arr_api_url "$app")"
        key="$(__arr_api_key "$app")" || return 1
        count="$(STATE="$2" URL="$url" KEY="$key" python3 - <<'PY' 2>/dev/null
import json, os, urllib.request
enable = os.environ['STATE'] == 'on'
base = os.environ['URL']
headers = {'X-Api-Key': os.environ['KEY'], 'Content-Type': 'application/json'}
req = urllib.request.Request(base + '/api/v3/indexer', headers=headers)
indexers = json.load(urllib.request.urlopen(req, timeout=15))
changed = 0
for idx in indexers:
    for f in idx.get('fields', []):
        if f.get('name') in ('enableRss', 'enableAutomaticSearch'):
            f['value'] = enable
    put = urllib.request.Request(base + '/api/v3/indexer/' + str(idx['id']),
                                 data=json.dumps(idx).encode(),
                                 headers=headers, method='PUT')
    urllib.request.urlopen(put, timeout=15)
    changed += 1
print(changed)
PY
)"
        if [ -n "$count" ] && [ "$count" != 0 ]; then
            fmt_success "$app: RSS sync + automatic search turned $2 on $count indexer(s)."
        elif [ -n "$count" ]; then
            fmt_warning "$app: no indexers to update."
        else
            fmt_error "$app: failed to update indexers."
        fi
    done
}

# cave-arr-blocklist <radarr|sonarr> [limit] — recent blocklisted releases
cave-arr-blocklist() {
# complete: radarr|sonarr
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-arr-blocklist <radarr|sonarr> [limit]" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local limit="${2:-20}"

    local url key result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    fmt_heading "$app — Blocklist"
    echo ""

    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/blocklist?pageSize=$limit&sortKey=date&sortDirection=descending" \
        -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach $app"
        return 1
    fi

    echo "$result" | LIMIT="$limit" python3 -c "
import sys, json, os
data = json.load(sys.stdin)
items = data.get('records', [])
if not items:
    print('  Blocklist is empty.')
else:
    for item in items[:int(os.environ['LIMIT'])]:
        title = item.get('title', item.get('sourceTitle', '?'))
        date = (item.get('date', '') or '')[:10]
        print(f'  {date}  {title}')
" 2>/dev/null
}

# cave-arr-clear-blocklist <radarr|sonarr>
cave-arr-clear-blocklist() {
# complete: radarr|sonarr
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-arr-clear-blocklist <radarr|sonarr>" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }

    local url key
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1

    # *arr has no collection-wide DELETE on /blocklist (405); the supported
    # clear is the ClearBlocklist command. It is async: 201 = accepted, and
    # the wipe completes in the background.
    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/command" \
        -H "X-Api-Key: $key" -H "Content-Type: application/json" \
        -d '{"name":"ClearBlocklist"}' >/dev/null 2>&1; then
        fmt_success "Blocklist cleared for $app."
    else
        fmt_error "Failed to clear blocklist for $app."
        return 1
    fi
}

# cave-arr-missing-aired <radarr|sonarr> [limit]
cave-arr-missing-aired() {
# complete: radarr|sonarr
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-arr-missing-aired <radarr|sonarr> [limit]" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local limit="${2:-30}"

    local url key result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    fmt_heading "$app — Missing + Aired"
    echo ""

    if [ "$app" = radarr ]; then
        result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/movie?pageSize=1000" -H "X-Api-Key: $key" 2>/dev/null)"
        if [ $? -ne 0 ]; then
            fmt_error "Cannot reach $app"
            return 1
        fi
        echo "$result" | LIMIT="$limit" python3 -c "
import sys, json, os
try:
    items = json.load(sys.stdin)
except Exception as e:
    print(f'  Error parsing response: {e}')
    sys.exit(1)
missing = [m for m in items if m.get('monitored') and not m.get('hasFile') and m.get('isAvailable')]
if not missing:
    print('  Nothing missing that has been released.')
else:
    for m in missing[:int(os.environ['LIMIT'])]:
        print(f\"  {m.get('title', '?')} ({m.get('year', '?')})\")
    if len(missing) > int(os.environ['LIMIT']):
        print(f\"\n  ... and {len(missing) - int(os.environ['LIMIT'])} more\")
    print(f\"\n  {len(missing)} item(s) missing.\")
"
    else
        # Sonarr: the wanted/missing endpoint is already monitored + aired
        # episodes (the bare /missing endpoint returns 401 on current Sonarr).
        # Episode records do not embed the series, so resolve titles in-python
        # via a second API call rather than shipping a {id: title} map through
        # an env var (a large library can exceed the 128KB execve env limit and
        # fail silently). The map degrades to '?' titles if the fetch fails.
        result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/wanted/missing?pageSize=$limit&sortKey=airDateUtc&sortDirection=descending" \
            -H "X-Api-Key: $key" 2>/dev/null)"
        if [ $? -ne 0 ]; then
            fmt_error "Cannot reach $app"
            return 1
        fi
        echo "$result" | URL="$url" KEY="$key" LIMIT="$limit" python3 -c "
import sys, json, os, urllib.request
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f'  Error parsing response: {e}')
    sys.exit(1)
series = {}
try:
    base = os.environ['URL']
    headers = {'X-Api-Key': os.environ['KEY']}
    req = urllib.request.Request(base + '/api/v3/series?pageSize=1000', headers=headers)
    series = {s['id']: s.get('title', '?') for s in json.load(urllib.request.urlopen(req, timeout=int(os.environ.get('STACK_API_TIMEOUT_LIGHT', '10'))))}
except Exception:
    series = {}
records = data.get('records', [])
total = data.get('totalRecords', len(records))
if not records:
    print('  Nothing missing that has aired.')
else:
    for e in records[:int(os.environ['LIMIT'])]:
        sid = e.get('seriesId')
        series_title = series.get(str(sid), series.get(sid, '?'))
        season = e.get('seasonNumber', 0)
        number = e.get('episodeNumber', 0)
        title = e.get('title', '?')
        print(f\"  {series_title} S{season:02d}E{number:02d} {title}\")
    if total > len(records):
        print(f\"\n  ... and {total - len(records)} more\")
        print(f\"\n  {total} episode(s) missing.\")
"
    fi
}

# cave-cutoff-unmet <radarr|sonarr> [limit]
cave-cutoff-unmet() {
# complete: radarr|sonarr
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-cutoff-unmet <radarr|sonarr> [limit]" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local limit="${2:-10}"

    local url key result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    fmt_heading "$app — Cutoff Unmet"
    echo ""

    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/wanted/cutoff?pageSize=$limit" -H "X-Api-Key: $key" 2>/dev/null)"
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
records = data.get('records', [])
total = data.get('totalRecords', len(records))
if not records:
    print('  Nothing is below its quality cutoff.')
else:
    for item in records[:int(os.environ['LIMIT'])]:
        if 'series' in item:
            ep = item.get('episode', {})
            title = item.get('series', {}).get('title', '?')
            label = f\"S{ep.get('seasonNumber', 0):02d}E{ep.get('episodeNumber', 0):02d} {ep.get('title', '?')}\"
        else:
            title = item.get('title', '?')
            label = f\"({item.get('year', '?')})\"
        print(f'  {title} {label}')
    if total > len(records):
        print(f'\n  ... and {total - len(records)} more')
    print(f'\n  {total} item(s) below cutoff.')
"
}
