# ============================================================================
# cave-loop-ratings — loop detection + rating lookups
# ============================================================================
# desc: loop candidates, exclude, unmonitor, tmdb-missing, rating lookups
# ============================================================================

# cave-loop-candidates <radarr|sonarr> — titles with repeated download failures
function cave-loop-candidates --description 'titles with repeated download failures'
# complete: radarr|sonarr
    if test (count $argv) -ne 1
        echo "Usage: cave-loop-candidates <radarr|sonarr>" >&2
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
    fmt_heading "$app — Loop Candidates"
    echo ""

    # Items with multiple failed grabs in history
    set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/history?pageSize=200&eventTypes=grabFailed" \
        -H "X-Api-Key: $key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach $app"
        return 1
    end

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
end

# cave-loop-exclude <movie-id> [-y|--yes] — add a Radarr movie to Exclusions
function cave-loop-exclude --description 'add a Radarr movie to Exclusions (prompts unless -y)'
# complete: -y|--yes
    if test (count $argv) -lt 1
        echo "Usage: cave-loop-exclude <movie-id> [-y|--yes]" >&2
        return 1
    end
    set -l id "$argv[1]"
    if not contains -- -y $argv; and not contains -- --yes $argv
        printf "Exclude movie %s from all future grabs? [y/N] " "$id"
        set -l confirm
        read -l confirm
        if test "$confirm" != y; and test "$confirm" != Y
            echo "Cancelled."
            return 1
        end
    end

    set -l url (__arr_api_url radarr)
    set -l key (__arr_api_key radarr); or return 1

    # Exclusions are keyed by TMDb id, so resolve the movie first
    set -l movie (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/movie/$id" -H "X-Api-Key: $key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot fetch movie $id from Radarr"
        return 1
    end
    set -l tmdb_id (echo "$movie" | python3 -c "
import sys, json
m = json.load(sys.stdin)
print(m.get('tmdbId', ''))
" 2>/dev/null)
    set -l title (echo "$movie" | python3 -c "
import sys, json
m = json.load(sys.stdin)
print(m.get('title', '?').replace(chr(10), ' '))
" 2>/dev/null)

    if test -z "$tmdb_id"
        fmt_error "Movie $id has no TMDb id — cannot add exclusion."
        return 1
    end

    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/exclusions" \
        -H "X-Api-Key: $key" \
        -H "Content-Type: application/json" \
        -d "{\"tmdbId\": $tmdb_id, \"movieTitle\": \"$title\"}" >/dev/null 2>&1
        fmt_success "Excluded '$title' (tmdb $tmdb_id) from all future grabs."
    else
        fmt_error "Failed to add exclusion."
        return 1
    end
end

# cave-loop-unmonitor <radarr|sonarr> <id> [-y|--yes]
function cave-loop-unmonitor --description 'unmonitor an item on an arr app (prompts unless -y)'
# complete: radarr|sonarr -y|--yes
    if test (count $argv) -lt 2
        echo "Usage: cave-loop-unmonitor <radarr|sonarr> <id> [-y|--yes]" >&2
        return 1
    end
    set -l app (__stack_arr_app "$argv[1]")
    if test $status -ne 0
        echo "Invalid app: $argv[1]" >&2
        return 1
    end
    set -l id "$argv[2]"
    if not contains -- -y $argv; and not contains -- --yes $argv
        printf "Unmonitor item %s on %s? [y/N] " "$id" "$app"
        set -l confirm
        read -l confirm
        if test "$confirm" != y; and test "$confirm" != Y
            echo "Cancelled."
            return 1
        end
    end

    set -l url (__arr_api_url "$app")
    set -l key (__arr_api_key "$app"); or return 1
    set -l endpoint "movie"
    test "$app" = sonarr; and set endpoint "series"

    # Get current item, then update monitored=false
    set -l item (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/$endpoint/$id" -H "X-Api-Key: $key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot fetch item $id from $app"
        return 1
    end

    echo "$item" | URL="$url" KEY="$key" ID="$id" ENDPOINT="$endpoint" APP="$app" STACK_API_TIMEOUT_MUTATE="$STACK_API_TIMEOUT_MUTATE" python3 -c "
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
end

# cave-tmdb-missing — scan libraries for items with no TMDb link
function cave-tmdb-missing --description 'scan Plex libraries for items with no TMDb link'
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"
    if test -z "$token"
        fmt_error "PLEX_TOKEN not set"
        return 1
    end

    fmt_heading "TMDb Missing Check"
    echo ""

    set -l sections (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach Plex"
        return 1
    end

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
end

# cave-rating-imdb <imdb-id> — a title's IMDb rating via OMDb
function cave-rating-imdb --description "a title's IMDb rating via OMDb"
    if test (count $argv) -ne 1
        echo "Usage: cave-rating-imdb <imdb-id>" >&2
        return 1
    end

    set -l omdb_key "$OMDB_KEY"
    if test -z "$omdb_key"
        fmt_error "OMDB_KEY not set"
        return 1
    end

    set -l result (__stack_curl "$STACK_API_TIMEOUT_HEAVY" -sf "http://www.omdbapi.com/?i=$argv[1]&apikey=$omdb_key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach OMDb API"
        return 1
    end

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
end

# cave-rating-mdblist <query> — a title's MDBList score + per-source ratings
function cave-rating-mdblist --description "a title's MDBList score + per-source ratings"
    if test (count $argv) -ne 1
        echo "Usage: cave-rating-mdblist <imdb-id-or-title>" >&2
        return 1
    end

    set -l mdblist_key "$MDBLIST_KEY"
    if test -z "$mdblist_key"
        fmt_error "MDBLIST_KEY not set"
        return 1
    end

    set -l payload (python3 -c 'import json, sys; print(json.dumps({"query": sys.argv[1]}))' "$argv[1]")
    set -l result (__stack_curl "$STACK_API_TIMEOUT_HEAVY" -sf -X POST "https://api.mdblist.com/api/search?apikey=$mdblist_key" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach MDBList API"
        return 1
    end

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
end
