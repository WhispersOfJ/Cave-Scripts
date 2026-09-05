# ============================================================================
# cave-lists — MDBList + Letterboxd list tracking and imports
# ============================================================================
# desc: mdblist and letterboxd track/untrack/tracked/import/history commands
# ============================================================================

# --- shared tracking-file helpers -------------------------------------------
__list_track() {
    # $1 = tracked file, $2 = url, $3 = label
    local tracked_file="$1" url="$2" label="$3"
    mkdir -p "$(dirname "$tracked_file")"
    if grep -qF "$url" "$tracked_file" 2>/dev/null; then
        fmt_warning "Already tracked: $url"
        return 0
    fi
    echo "$url|$label" >>"$tracked_file"
    if [ -n "$label" ]; then
        fmt_success "Now tracking: $url (label: $label)"
    else
        fmt_success "Now tracking: $url"
    fi
}

__list_untrack() {
    local tracked_file="$1" url="$2"
    if [ ! -f "$tracked_file" ]; then
        fmt_warning "No lists tracked."
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    grep -vF "$url" "$tracked_file" >"$tmp" 2>/dev/null
    mv "$tmp" "$tracked_file"
    fmt_success "Stopped tracking: $url"
}

__list_tracked() {
    local tracked_file="$1" heading="$2"
    fmt_heading "$heading"
    echo ""
    if [ ! -f "$tracked_file" ]; then
        echo "  No lists tracked."
        return 0
    fi
    local count=0 line url label
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        url="${line%%|*}"
        label="${line#*|}"
        [ "$label" = "$line" ] && label=""
        if [ -n "$label" ]; then
            echo "  $label  $url"
        else
            echo "  $url"
        fi
        count=$((count + 1))
    done <"$tracked_file"
    if [ "$count" -eq 0 ]; then
        echo "  No lists tracked."
    else
        echo ""
        echo "  $count list(s) tracked."
    fi
}

# --- MDBList -----------------------------------------------------------------

# cave-mdblist-track <list-url> [--label TEXT]
cave-mdblist-track() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-mdblist-track <list-url> [--label TEXT]" >&2
        return 1
    fi
    local url="$1" label=""
    local i
    for ((i = 1; i <= $#; i++)); do
        if [ "${(P)i}" = "--label" ]; then
            if [ "$i" -eq "$#" ]; then
                echo "--label given but no value provided" >&2
                return 1
            fi
            local j=$((i + 1))
            label="${(P)j}"
        fi
    done
    __list_track "$HOME/.config/bearcave/mdblist-tracked.txt" "$url" "$label"
}

# cave-mdblist-untrack <list-url>
cave-mdblist-untrack() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-mdblist-untrack <list-url>" >&2
        return 1
    fi
    __list_untrack "$HOME/.config/bearcave/mdblist-tracked.txt" "$1"
}

# cave-mdblist-tracked — every MDBList list currently registered
cave-mdblist-tracked() {
    __list_tracked "$HOME/.config/bearcave/mdblist-tracked.txt" "Tracked MDBList Lists"
}

# cave-mdblist-import <numeric-list-id | mdblist.com/lists/<user>/<slug> URL>
cave-mdblist-import() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-mdblist-import <list-id-or-url> [--no-search] [--dry-run] [--limit N]" >&2
        return 1
    fi
    local list_url="$1"

    local mdblist_key="${MDBLIST_KEY:-}"
    if [ -z "$mdblist_key" ]; then
        fmt_error "MDBLIST_KEY not set"
        return 1
    fi

    fmt_heading "MDBList Import"
    echo ""

    # Numeric ids use /api/lists/{id}; site URLs are /lists/<user>/<slug>
    local endpoint=""
    if [[ "$list_url" =~ ^[0-9]+$ ]]; then
        endpoint="https://api.mdblist.com/api/lists/$list_url?apikey=$mdblist_key"
    elif [[ "$list_url" =~ ^https?://(www\.)?mdblist\.com/lists/[^/?#]+/[^/?#]+ ]]; then
        local path
        path="$(echo "$list_url" | sed -E 's|^https?://(www\.)?mdblist\.com/||' | cut -d'?' -f1)"
        endpoint="https://api.mdblist.com/$path?apikey=$mdblist_key"
    else
        fmt_error "Cannot parse list from '$list_url' (use a numeric list id or an mdblist.com/lists/<user>/<slug> URL)"
        return 1
    fi

    local result
    result="$(__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$endpoint" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot fetch list from MDBList"
        return 1
    fi

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
}

# cave-mdblist-history — recent MDBList sync runs
cave-mdblist-history() {
    local log_dir="/var/log/mdblist"
    if [ -d "$log_dir" ]; then
        fmt_heading "MDBList Sync History"
        echo ""
        ls -lt "$log_dir"/*.log 2>/dev/null | head -10 | while IFS= read -r line; do
            echo "  $line"
        done
    else
        fmt_heading "MDBList"
        echo ""
        echo "  No local sync logs found."
        echo "  MDBList sync is not configured in this stack."
    fi
}

# --- Letterboxd --------------------------------------------------------------

# cave-letterboxd-track <list-url> [--label TEXT]
cave-letterboxd-track() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-letterboxd-track <list-url> [--label TEXT]" >&2
        return 1
    fi
    local url="$1" label=""
    local i
    for ((i = 1; i <= $#; i++)); do
        if [ "${(P)i}" = "--label" ]; then
            if [ "$i" -eq "$#" ]; then
                echo "--label given but no value provided" >&2
                return 1
            fi
            local j=$((i + 1))
            label="${(P)j}"
        fi
    done
    __list_track "$HOME/.config/bearcave/letterboxd-tracked.txt" "$url" "$label"
}

# cave-letterboxd-untrack <list-url>
cave-letterboxd-untrack() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-letterboxd-untrack <list-url>" >&2
        return 1
    fi
    __list_untrack "$HOME/.config/bearcave/letterboxd-tracked.txt" "$1"
}

# cave-letterboxd-tracked — every Letterboxd list currently registered
cave-letterboxd-tracked() {
    __list_tracked "$HOME/.config/bearcave/letterboxd-tracked.txt" "Tracked Letterboxd Lists"
}

# cave-letterboxd-import <type> <url-or-path> [--limit N]
cave-letterboxd-import() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: cave-letterboxd-import <type> <url-or-path> [--limit N]" >&2
        echo "Types: film, list, watchlist, watched, collection, filmography, popular, random" >&2
        return 1
    fi
    local type="$1" list_url="$2"

    local limit=10
    local i
    for ((i = 1; i <= $#; i++)); do
        if [ "${(P)i}" = "--limit" ]; then
            if [ "$i" -eq "$#" ]; then
                echo "--limit given but no value provided" >&2
                return 1
            fi
            local j=$((i + 1))
            limit="${(P)j}"
        fi
    done

    fmt_heading "Letterboxd Import ($type)"
    echo ""

    # Accept a full URL or a bare list path
    local feed_url="$list_url"
    if [[ "$list_url" != http* ]]; then
        feed_url="https://letterboxd.com/$list_url/"
    fi

    local rss_url="$feed_url/rss/"
    local result
    result="$(__stack_curl "$STACK_API_TIMEOUT_HEAVY" -sfL "$rss_url" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        fmt_error "Cannot fetch Letterboxd feed from $rss_url"
        return 1
    fi

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
}

# cave-letterboxd-history — recent Letterboxd sync runs
cave-letterboxd-history() {
    local log_dir="/var/log/letterboxd"
    if [ -d "$log_dir" ]; then
        fmt_heading "Letterboxd Sync History"
        echo ""
        ls -lt "$log_dir"/*.log 2>/dev/null | head -10 | while IFS= read -r line; do
            echo "  $line"
        done
    else
        fmt_heading "Letterboxd"
        echo ""
        echo "  No local sync logs found."
        echo "  Letterboxd sync is not configured in this stack."
    fi
}
