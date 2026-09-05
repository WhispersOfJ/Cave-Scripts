# ============================================================================
# cave-lists — MDBList + Letterboxd list tracking and imports
# ============================================================================
# desc: mdblist and letterboxd track/untrack/tracked/import/history commands
# ============================================================================

# --- shared tracking-file helpers -------------------------------------------
function __list_track --description 'append a tracked list url|label (skip duplicates)'
    # $1 = tracked file, $2 = url, $3 = label
    set -l tracked_file "$argv[1]"
    set -l url "$argv[2]"
    set -l label "$argv[3]"
    mkdir -p (dirname "$tracked_file")
    if grep -qF "$url" "$tracked_file" 2>/dev/null
        fmt_warning "Already tracked: $url"
        return 0
    end
    echo "$url|$label" >>"$tracked_file"
    if test -n "$label"
        fmt_success "Now tracking: $url (label: $label)"
    else
        fmt_success "Now tracking: $url"
    end
end

function __list_untrack --description 'remove a tracked list line by url'
    set -l tracked_file "$argv[1]"
    set -l url "$argv[2]"
    if not test -f "$tracked_file"
        fmt_warning "No lists tracked."
        return 0
    end
    set -l tmp (mktemp)
    grep -vF "$url" "$tracked_file" >"$tmp" 2>/dev/null
    mv "$tmp" "$tracked_file"
    fmt_success "Stopped tracking: $url"
end

function __list_tracked --description 'print every tracked list with its label'
    set -l tracked_file "$argv[1]"
    set -l heading "$argv[2]"
    fmt_heading "$heading"
    echo ""
    if not test -f "$tracked_file"
        echo "  No lists tracked."
        return 0
    end
    set -l count 0
    while read -l line
        test -z "$line"; and continue
        set -l url (string split -m 1 '|' -- "$line")[1]
        set -l label ""
        set -l parts (string split -m 1 '|' -- "$line")
        if test (count $parts) -ge 2
            set label $parts[2]
        end
        if test -n "$label"
            echo "  $label  $url"
        else
            echo "  $url"
        end
        set count (math "$count + 1")
    end <"$tracked_file"
    if test "$count" -eq 0
        echo "  No lists tracked."
    else
        echo ""
        echo "  $count list(s) tracked."
    end
end

# --- MDBList -----------------------------------------------------------------

# cave-mdblist-track <list-url> [--label TEXT]
function cave-mdblist-track --description 'track an MDBList list locally'
    if test (count $argv) -lt 1
        echo "Usage: cave-mdblist-track <list-url> [--label TEXT]" >&2
        return 1
    end
    set -l url "$argv[1]"
    set -l label ""
    set -l argc (count $argv)
    for i in (seq 1 $argc)
        if test "$argv[$i]" = "--label"
            if test "$i" -eq "$argc"
                echo "--label given but no value provided" >&2
                return 1
            end
            set label "$argv[(math $i + 1)]"
        end
    end
    __list_track "$HOME/.config/bearcave/mdblist-tracked.txt" "$url" "$label"
end

# cave-mdblist-untrack <list-url>
function cave-mdblist-untrack --description 'stop tracking an MDBList list'
    if test (count $argv) -ne 1
        echo "Usage: cave-mdblist-untrack <list-url>" >&2
        return 1
    end
    __list_untrack "$HOME/.config/bearcave/mdblist-tracked.txt" "$argv[1]"
end

# cave-mdblist-tracked — every MDBList list currently registered
function cave-mdblist-tracked --description 'every MDBList list currently registered'
    __list_tracked "$HOME/.config/bearcave/mdblist-tracked.txt" "Tracked MDBList Lists"
end

# cave-mdblist-import <numeric-list-id | mdblist.com/lists/<user>/<slug> URL>
function cave-mdblist-import --description 'preview an MDBList list (id or site URL)'
    if test (count $argv) -lt 1
        echo "Usage: cave-mdblist-import <list-id-or-url> [--no-search] [--dry-run] [--limit N]" >&2
        return 1
    end
    set -l list_url "$argv[1]"

    set -l mdblist_key "$MDBLIST_KEY"
    if test -z "$mdblist_key"
        fmt_error "MDBLIST_KEY not set"
        return 1
    end

    fmt_heading "MDBList Import"
    echo ""

    # Numeric ids use /api/lists/{id}; site URLs are /lists/<user>/<slug>
    set -l endpoint ""
    if string match -qr '^[0-9]+$' -- "$list_url"
        set endpoint "https://api.mdblist.com/api/lists/$list_url?apikey=$mdblist_key"
    else if string match -qr '^https?://(www\.)?mdblist\.com/lists/[^/?#]+/[^/?#]+' -- "$list_url"
        set -l path (echo "$list_url" | sed -E 's|^https?://(www\.)?mdblist\.com/||' | cut -d'?' -f1)
        set endpoint "https://api.mdblist.com/$path?apikey=$mdblist_key"
    else
        fmt_error "Cannot parse list from '$list_url' (use a numeric list id or an mdblist.com/lists/<user>/<slug> URL)"
        return 1
    end

    set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$endpoint" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot fetch list from MDBList"
        return 1
    end

    echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('items', d.get('movies', []))
print(f\"  List: {d.get('name', '?')}\")
print(f\"  Items: {len(items)}\")
for item in items[:10]:
    title = item.get('title', item.get('name', '?'))
    year = item.get('year', '?')
    print(f'    {title} ({year})')
if len(items) > 10:
    print(f'    ... and {len(items) - 10} more')
" 2>/dev/null
end

# cave-mdblist-history — recent MDBList sync runs
function cave-mdblist-history --description 'recent MDBList sync runs'
    set -l log_dir "/var/log/mdblist"
    if test -d "$log_dir"
        fmt_heading "MDBList Sync History"
        echo ""
        ls -lt "$log_dir"/*.log 2>/dev/null | head -10 | while read -l line
            echo "  $line"
        end
    else
        fmt_heading "MDBList"
        echo ""
        echo "  No local sync logs found."
        echo "  MDBList sync is not configured in this stack."
    end
end

# --- Letterboxd --------------------------------------------------------------

# cave-letterboxd-track <list-url> [--label TEXT]
function cave-letterboxd-track --description 'track a Letterboxd list locally'
    if test (count $argv) -lt 1
        echo "Usage: cave-letterboxd-track <list-url> [--label TEXT]" >&2
        return 1
    end
    set -l url "$argv[1]"
    set -l label ""
    set -l argc (count $argv)
    for i in (seq 1 $argc)
        if test "$argv[$i]" = "--label"
            if test "$i" -eq "$argc"
                echo "--label given but no value provided" >&2
                return 1
            end
            set label "$argv[(math $i + 1)]"
        end
    end
    __list_track "$HOME/.config/bearcave/letterboxd-tracked.txt" "$url" "$label"
end

# cave-letterboxd-untrack <list-url>
function cave-letterboxd-untrack --description 'stop tracking a Letterboxd list'
    if test (count $argv) -ne 1
        echo "Usage: cave-letterboxd-untrack <list-url>" >&2
        return 1
    end
    __list_untrack "$HOME/.config/bearcave/letterboxd-tracked.txt" "$argv[1]"
end

# cave-letterboxd-tracked — every Letterboxd list currently registered
function cave-letterboxd-tracked --description 'every Letterboxd list currently registered'
    __list_tracked "$HOME/.config/bearcave/letterboxd-tracked.txt" "Tracked Letterboxd Lists"
end

# cave-letterboxd-import <type> <url-or-path> [--limit N]
function cave-letterboxd-import --description 'preview a Letterboxd list via its RSS feed'
    if test (count $argv) -lt 2
        echo "Usage: cave-letterboxd-import <type> <url-or-path> [--limit N]" >&2
        echo "Types: film, list, watchlist, watched, collection, filmography, popular, random" >&2
        return 1
    end
    set -l type "$argv[1]"
    set -l list_url "$argv[2]"

    set -l limit 10
    set -l argc (count $argv)
    for i in (seq 1 $argc)
        if test "$argv[$i]" = "--limit"
            if test "$i" -eq "$argc"
                echo "--limit given but no value provided" >&2
                return 1
            end
            set limit "$argv[(math $i + 1)]"
        end
    end

    fmt_heading "Letterboxd Import ($type)"
    echo ""

    # Accept a full URL or a bare list path
    set -l feed_url "$list_url"
    if not string match -q 'http*' -- "$list_url"
        set feed_url "https://letterboxd.com/$list_url/"
    end

    set -l rss_url "$feed_url/rss/"
    set -l result (__stack_curl "$STACK_API_TIMEOUT_HEAVY" -sfL "$rss_url" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot fetch Letterboxd feed from $rss_url"
        return 1
    end

    # Parse RSS for film titles
    echo "$result" | LIMIT="$limit" python3 -c "
import sys, re, os
xml = sys.stdin.read()
titles = re.findall(r'<title>([^<]+)</title>', xml)
limit = int(os.environ['LIMIT'])
# Skip the first one (feed title)
shown = titles[1:1 + limit]
for t in shown:
    print(f'  {t}')
if len(titles) - 1 > len(shown):
    print(f'  ... and {len(titles) - 1 - len(shown)} more')
if len(titles) <= 1:
    print('  No items found in feed.')
"
end

# cave-letterboxd-history — recent Letterboxd sync runs
function cave-letterboxd-history --description 'recent Letterboxd sync runs'
    set -l log_dir "/var/log/letterboxd"
    if test -d "$log_dir"
        fmt_heading "Letterboxd Sync History"
        echo ""
        ls -lt "$log_dir"/*.log 2>/dev/null | head -10 | while read -l line
            echo "  $line"
        end
    else
        fmt_heading "Letterboxd"
        echo ""
        echo "  No local sync logs found."
        echo "  Letterboxd sync is not configured in this stack."
    end
end
