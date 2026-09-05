# ============================================================================
# cave-plex-core.sh — core Plex commands
# ============================================================================
# desc: core plex sessions, scan, butler, trash, analyze commands
# ============================================================================

# cave-plex-sessions — who is watching what
cave-plex-sessions() {
    fmt_heading "Plex Sessions"
    echo ""
    __plex_api GET "/status/sessions" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f'  Error parsing response: {e}')
    sys.exit(1)
mc = data.get('MediaContainer', {})
sessions = mc.get('Metadata', [])
if not sessions:
    print('  No active sessions.')
else:
    for s in sessions:
        user = s.get('User', {}).get('title', '?')
        title = s.get('title', '?')
        grandparent = s.get('grandparentTitle', '')
        label = f'{grandparent} — {title}' if grandparent else title
        player = s.get('Player', {}).get('title', '?')
        state = s.get('Player', {}).get('state', '?')
        print(f'  [{state}] {user} — {label} ({player})')
    print(f'')
    print(f'  {len(sessions)} session(s).')
" 2>/dev/null
}

# cave-plex-recently-added [limit]
cave-plex-recently-added() {
    local limit="${1:-10}"
    fmt_heading "Plex — Recently Added"
    echo ""
    __plex_api GET "/library/recentlyAdded?X-Plex-Container-Size=$limit" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f'  Error parsing response: {e}')
    sys.exit(1)
mc = data.get('MediaContainer', {})
items = mc.get('Metadata', [])
if not items:
    print('  Nothing recently added.')
else:
    for item in items:
        title = item.get('title', '?')
        kind = item.get('type', '?')
        added = item.get('addedAt', '')
        print(f'  [{kind}] {title}')
    print(f'')
    print(f'  {len(items)} item(s).')
" 2>/dev/null
}

# cave-plex-libraries — list library sections
cave-plex-libraries() {
    fmt_heading "Plex Libraries"
    echo ""
    __plex_api GET "/library/sections" -H "Accept: application/json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f'  Error parsing response: {e}')
    sys.exit(1)
mc = data.get('MediaContainer', {})
sections = mc.get('Directory', [])
if not sections:
    print('  No libraries found.')
else:
    for s in sections:
        print(f\"  [{s.get('type', '?')}] {s.get('title', '?')} (key={s.get('key', '?')})\")
    print(f'')
    print(f'  {len(sections)} library(ies).')
" 2>/dev/null
}

# cave-plex refresh-libraries|empty-trash|analyze|scan — Plex maintenance actions
cave-plex() {
# complete: refresh-libraries|empty-trash|analyze|scan
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-plex <refresh-libraries|empty-trash|analyze|scan>" >&2
        return 1
    fi
    local action="$1"
    local plex_url="${PLEX_URL:-http://localhost:32400}"
    local token="${PLEX_TOKEN:-}"
    if [ -z "$token" ]; then
        echo "PLEX_TOKEN not set" >&2
        return 1
    fi

    case "$action" in
        refresh-libraries|scan)
            local sections failed=0 total=0
            sections="$(__plex_api GET "/library/sections" -H "Accept: application/json" 2>/dev/null \
                | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", [])]' 2>/dev/null)"
            if [ -z "$sections" ]; then
                fmt_error "Cannot reach Plex or no libraries found."
                return 1
            fi
            for key in $sections; do
                total=$((total + 1))
                __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$plex_url/library/sections/$key/refresh?X-Plex-Token=$token" >/dev/null 2>&1 \
                    || failed=$((failed + 1))
            done
            if [ "$failed" -eq 0 ]; then
                fmt_success "Library scan triggered for $total section(s)."
            else
                fmt_error "Scan triggered for $((total - failed)) section(s); $failed failed."
                return 1
            fi
            ;;
        empty-trash)
            local sections failed=0 total=0
            sections="$(__plex_api GET "/library/sections" -H "Accept: application/json" 2>/dev/null \
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
            ;;
        analyze)
            local sections failed=0 total=0
            sections="$(__plex_api GET "/library/sections" -H "Accept: application/json" 2>/dev/null \
                | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", [])]' 2>/dev/null)"
            if [ -z "$sections" ]; then
                fmt_error "Cannot reach Plex or no libraries found."
                return 1
            fi
            for key in $sections; do
                total=$((total + 1))
                __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X PUT "$plex_url/library/sections/$key/analyze?X-Plex-Token=$token" >/dev/null 2>&1 \
                    || failed=$((failed + 1))
            done
            if [ "$failed" -eq 0 ]; then
                fmt_success "Analysis triggered for $total section(s)."
            else
                fmt_error "Analysis triggered for $((total - failed)) section(s); $failed failed."
                return 1
            fi
            ;;
        *)
            echo "Unknown action: $action (use refresh-libraries, empty-trash, analyze, scan)" >&2
            return 1
            ;;
    esac
}

# complete: <butler-task>
# cave-plex-butler <task> — trigger one butler task
cave-plex-butler() {
# danger: true (arbitrary butler task; several delete files)
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-plex-butler <task>" >&2
        return 1
    fi
    __plex_butler "$1"
}

# cave-plex-butler-all — trigger the common butler maintenance tasks
cave-plex-butler-all() {
# danger: true (CleanOldBundles deletes old bundles)
    fmt_heading "Plex Butler — All Tasks"
    echo ""
    local task
    for task in CleanOldBundles OptimizeDatabase RefreshLocalMedia BackupDatabase; do
        __plex_butler "$task"
    done
}
