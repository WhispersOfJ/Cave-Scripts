# ============================================================================
# cave-plex-core — core Plex commands
# ============================================================================
# desc: core plex sessions, scan, butler, trash, analyze commands
# ============================================================================

# cave-plex-sessions — who is watching what
function cave-plex-sessions --description 'Plex: who is watching what'
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
end

# cave-plex-recently-added [limit]
function cave-plex-recently-added --description 'Plex: recently added items'
    set -l limit "$argv[1]"
    test -n "$limit"; or set limit 10
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
end

# cave-plex-libraries — list library sections
function cave-plex-libraries --description 'Plex: list library sections'
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
end

# cave-plex refresh-libraries|empty-trash|analyze|scan — Plex maintenance actions
function cave-plex --description 'Plex maintenance: refresh-libraries|empty-trash|analyze|scan'
# complete: refresh-libraries|empty-trash|analyze|scan
    if test (count $argv) -ne 1
        echo "Usage: cave-plex <refresh-libraries|empty-trash|analyze|scan>" >&2
        return 1
    end
    set -l action "$argv[1]"
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"
    if test -z "$token"
        echo "PLEX_TOKEN not set" >&2
        return 1
    end

    switch $action
        case refresh-libraries scan
            set -l sections (__plex_api GET "/library/sections" -H "Accept: application/json" 2>/dev/null \
                | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", [])]' 2>/dev/null)
            if test -z "$sections"
                fmt_error "Cannot reach Plex or no libraries found."
                return 1
            end
            set -l failed 0
            set -l total 0
            for key in $sections
                set total (math "$total + 1")
                __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$plex_url/library/sections/$key/refresh?X-Plex-Token=$token" >/dev/null 2>&1
                or set failed (math "$failed + 1")
            end
            if test "$failed" -eq 0
                fmt_success "Library scan triggered for $total section(s)."
            else
                fmt_error "Scan triggered for "(math "$total - $failed")" section(s); $failed failed."
                return 1
            end
        case empty-trash
            set -l sections (__plex_api GET "/library/sections" -H "Accept: application/json" 2>/dev/null \
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
        case analyze
            set -l sections (__plex_api GET "/library/sections" -H "Accept: application/json" 2>/dev/null \
                | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", [])]' 2>/dev/null)
            if test -z "$sections"
                fmt_error "Cannot reach Plex or no libraries found."
                return 1
            end
            set -l failed 0
            set -l total 0
            for key in $sections
                set total (math "$total + 1")
                __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X PUT "$plex_url/library/sections/$key/analyze?X-Plex-Token=$token" >/dev/null 2>&1
                or set failed (math "$failed + 1")
            end
            if test "$failed" -eq 0
                fmt_success "Analysis triggered for $total section(s)."
            else
                fmt_error "Analysis triggered for "(math "$total - $failed")" section(s); $failed failed."
                return 1
            end
        case '*'
            echo "Unknown action: $action (use refresh-libraries, empty-trash, analyze, scan)" >&2
            return 1
    end
end

# complete: <butler-task>
# cave-plex-butler <task> — trigger one butler task
function cave-plex-butler --description 'trigger one Plex Butler task'
# danger: true (arbitrary butler task; several delete files)
    if test (count $argv) -ne 1
        echo "Usage: cave-plex-butler <task>" >&2
        return 1
    end
    __plex_butler "$argv[1]"
end

# cave-plex-butler-all — trigger the common butler maintenance tasks
function cave-plex-butler-all --description 'trigger the common Plex Butler maintenance tasks'
# danger: true (CleanOldBundles deletes old bundles)
    fmt_heading "Plex Butler — All Tasks"
    echo ""
    for task in CleanOldBundles OptimizeDatabase RefreshLocalMedia BackupDatabase
        __plex_butler "$task"
    end
end
