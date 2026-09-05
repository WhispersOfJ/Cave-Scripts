# ============================================================================
# cave-loop-ratings — loop detection + rating lookups
# ============================================================================
# desc: loop candidates, exclude, unmonitor, tmdb-missing, rating lookups
# ============================================================================

# cave-loop-candidates <radarr|sonarr> — titles with repeated download failures
cave-loop-candidates() {
# complete: radarr|sonarr
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-loop-candidates <radarr|sonarr>" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }

    local url key result
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    fmt_heading "$app — Loop Candidates"
    echo ""

    # Items with multiple failed grabs in history
    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/history?pageSize=200&eventTypes=grabFailed" \
        -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach $app"
        return 1
    fi

    echo "$result" | python3 -c "
import sys, json
from collections import Counter
data = json.load(sys.stdin)
items = data.get('records', []) if isinstance(data, dict) else data
# Count failures per title
fails = Counter()
for item in items:
    title = item.get('sourceTitle', item.get('title', '?'))
    fails[title] += 1
# Show items with 3+ failures
looping = [(t, c) for t, c in fails.most_common() if c >= 3]
if not looping:
    print('  No loop candidates found (no items with 3+ failures).')
else:
    for title, count in looping:
        print(f'  [{count} failures] {title}')
" 2>/dev/null
}

# cave-loop-exclude <movie-id> [-y|--yes] — add a Radarr movie to Exclusions
cave-loop-exclude() {
# complete: -y|--yes
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-loop-exclude <movie-id> [-y|--yes]" >&2
        return 1
    fi
    local id="$1"
    if ! printf '%s\n' "$@" | grep -qx -- -y && ! printf '%s\n' "$@" | grep -qx -- --yes; then
        local confirm
        printf "Exclude movie %s from all future grabs? [y/N] " "$id"
        read -r confirm
        if [ "$confirm" != y ] && [ "$confirm" != Y ]; then
            echo "Cancelled."
            return 1
        fi
    fi

    local url key movie tmdb_id title
    url="$(__arr_api_url radarr)"
    key="$(__arr_api_key radarr)" || return 1

    # Exclusions are keyed by TMDb id, so resolve the movie first
    movie="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/movie/$id" -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot fetch movie $id from Radarr"
        return 1
    fi
    tmdb_id="$(echo "$movie" | python3 -c "
import sys, json
m = json.load(sys.stdin)
print(m.get('tmdbId', ''))
" 2>/dev/null)"
    title="$(echo "$movie" | python3 -c "
import sys, json
m = json.load(sys.stdin)
print(m.get('title', '?').replace(chr(10), ' '))
" 2>/dev/null)"

    if [ -z "$tmdb_id" ]; then
        fmt_error "Movie $id has no TMDb id — cannot add exclusion."
        return 1
    fi

    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/exclusions" \
        -H "X-Api-Key: $key" \
        -H "Content-Type: application/json" \
        -d "{\"tmdbId\": $tmdb_id, \"movieTitle\": \"$title\"}" >/dev/null 2>&1; then
        fmt_success "Excluded '$title' (tmdb $tmdb_id) from all future grabs."
    else
        fmt_error "Failed to add exclusion."
        return 1
    fi
}

# cave-loop-unmonitor <radarr|sonarr> <id> [-y|--yes]
cave-loop-unmonitor() {
# complete: radarr|sonarr -y|--yes
    if [ "$#" -lt 2 ]; then
        echo "Usage: cave-loop-unmonitor <radarr|sonarr> <id> [-y|--yes]" >&2
        return 1
    fi
    local app
    app="$(__stack_arr_app "$1")" || { echo "Invalid app: $1" >&2; return 1; }
    local id="$2"
    if ! printf '%s\n' "$@" | grep -qx -- -y && ! printf '%s\n' "$@" | grep -qx -- --yes; then
        local confirm
        printf "Unmonitor item %s on %s? [y/N] " "$id" "$app"
        read -r confirm
        if [ "$confirm" != y ] && [ "$confirm" != Y ]; then
            echo "Cancelled."
            return 1
        fi
    fi

    local url key endpoint
    url="$(__arr_api_url "$app")"
    key="$(__arr_api_key "$app")" || return 1
    endpoint="movie"
    [ "$app" = sonarr ] && endpoint="series"

    # Get current item, then update monitored=false
    local item
    item="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/$endpoint/$id" -H "X-Api-Key: $key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot fetch item $id from $app"
        return 1
    fi

    echo "$item" | URL="$url" KEY="$key" ID="$id" ENDPOINT="$endpoint" APP="$app" python3 -c "
import sys, json, subprocess, os
item = json.load(sys.stdin)
item['monitored'] = False
subprocess.run([
    'curl', '-sf', '--connect-timeout', '5', '--max-time', os.environ.get('STACK_API_TIMEOUT_MUTATE', '20'), '-X', 'PUT',
    os.environ['URL'] + '/api/v3/' + os.environ['ENDPOINT'] + '/' + os.environ['ID'],
    '-H', 'X-Api-Key: ' + os.environ['KEY'],
    '-H', 'Content-Type: application/json',
    '-d', json.dumps(item)
], capture_output=True)
print(f\"  Unmonitored: {item.get('title', '?')} on {os.environ['APP']}\")
" 2>/dev/null
}

# cave-tmdb-missing — scan libraries for items with no TMDb link
cave-tmdb-missing() {
    local plex_url="${PLEX_URL:-http://localhost:32400}"
    local token="${PLEX_TOKEN:-}"
    if [ -z "$token" ]; then
        fmt_error "PLEX_TOKEN not set"
        return 1
    fi

    fmt_heading "TMDb Missing Check"
    echo ""

    local sections
    sections="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach Plex"
        return 1
    fi

    echo "$sections" | PLEX_URL="$plex_url" TOKEN="$token" python3 -c "
import sys, json, urllib.request, os

plex_url = os.environ['PLEX_URL']
token = os.environ['TOKEN']
data = json.load(sys.stdin)
total_missing = 0

for section in data.get('MediaContainer', {}).get('Directory', []):
    key = section.get('key')
    title = section.get('title', '?')
    stype = section.get('type', '')
    if stype not in ('movie', 'show'):
        continue

    url = f'{plex_url}/library/sections/{key}/all?X-Plex-Token={token}&pageSize=500'
    req = urllib.request.Request(url, headers={'Accept': 'application/json'})
    r = urllib.request.urlopen(req, timeout=30)
    items = json.loads(r.read()).get('MediaContainer', {}).get('Metadata', [])

    missing = []
    for item in items:
        guids = item.get('Guid', [])
        has_tmdb = any('tmdb' in g.get('id', '').lower() for g in guids)
        if not has_tmdb:
            missing.append(item.get('title', '?'))

    if missing:
        print(f'  {title}: {len(missing)} items without TMDb')
        for m in missing[:10]:
            print(f'    - {m}')
        if len(missing) > 10:
            print(f'    ... and {len(missing) - 10} more')
        total_missing += len(missing)

if total_missing == 0:
    print('  All items have TMDb links.')
else:
    print(f'\n  Total: {total_missing} items without TMDb')
" 2>/dev/null
}

# cave-rating-imdb <imdb-id> — a title's IMDb rating via OMDb
cave-rating-imdb() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-rating-imdb <imdb-id>" >&2
        return 1
    fi

    local omdb_key="${OMDB_KEY:-}"
    if [ -z "$omdb_key" ]; then
        fmt_error "OMDB_KEY not set"
        return 1
    fi

    local result
    result="$(__stack_curl "$STACK_API_TIMEOUT_HEAVY" -sf "http://www.omdbapi.com/?i=$1&apikey=$omdb_key" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach OMDb API"
        return 1
    fi

    echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if d.get('Response') == 'False':
    print(f\"  Not found: {d.get('Error', '?')}\")
else:
    print(f\"  {d.get('Title', '?')} ({d.get('Year', '?')})\")
    print(f\"  IMDb: {d.get('imdbRating', '?')}/10 ({d.get('imdbVotes', '?')} votes)\")
    print(f\"  Rated: {d.get('Rated', '?')}  Runtime: {d.get('Runtime', '?')}\")
" 2>/dev/null
}

# cave-rating-mdblist <query> — a title's MDBList score + per-source ratings
cave-rating-mdblist() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-rating-mdblist <imdb-id-or-title>" >&2
        return 1
    fi

    local mdblist_key="${MDBLIST_KEY:-}"
    if [ -z "$mdblist_key" ]; then
        fmt_error "MDBLIST_KEY not set"
        return 1
    fi

    local payload result
    payload="$(python3 -c 'import json, sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"
    result="$(__stack_curl "$STACK_API_TIMEOUT_HEAVY" -sf -X POST "https://api.mdblist.com/api/search?apikey=$mdblist_key" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot reach MDBList API"
        return 1
    fi

    echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d if isinstance(d, list) else d.get('results', d.get('movies', []))
if not results:
    print('  No results for that query.')
    sys.exit(0)
item = results[0]
print(f\"  {item.get('title', '?')} ({item.get('year', '?')})\")
score = item.get('score')
print(f\"  MDBList: {score if score is not None else '?'}/100\")
for r in item.get('ratings', []):
    print(f\"  {r.get('source', '?')}: {r.get('score', '?')}\")
"
}
