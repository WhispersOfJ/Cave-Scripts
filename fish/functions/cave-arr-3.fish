# ============================================================================
# cave-arr-3 — arr commands (part 3) + summary commands
# ============================================================================
# desc: arr command triggers, backlog status, import lists, prowlarr indexers
# ============================================================================

# cave-arr <radarr|sonarr> <rss-sync|search-missing|unstick|unstick-importing>
function cave-arr --description 'trigger arr commands (rss-sync, search-missing, unstick, unstick-importing)'
# complete: <arr-app> rss-sync|search-missing|unstick|unstick-importing
    if test (count $argv) -lt 2
        echo "Usage: cave-arr <radarr|sonarr> <rss-sync|search-missing|unstick|unstick-importing>" >&2
        return 1
    end
    set -l app (__stack_arr_app "$argv[1]")
    if test $status -ne 0
        echo "Invalid app: $argv[1] (use radarr or sonarr)" >&2
        return 1
    end
    set -l cmd "$argv[2]"

    # Map commands to Arr API command names
    switch $cmd
        case rss-sync
            set -l api_cmd "RssSync"
        case search-missing
            set -l api_cmd "MissingEpisodeSearch"
        case unstick
            set -l api_cmd "RefreshMonitoredDownloads"
        case unstick-importing
            set -l api_cmd "ManualImport"
        case '*'
            echo "Unknown command: $cmd" >&2
            return 1
    end

    set -l url (__arr_api_url "$app")
    set -l key (__arr_api_key "$app"); or set key ""

    if test -z "$url"
        echo "Cannot determine URL for $app" >&2
        return 1
    end
    if test -z "$key"
        echo "Cannot determine API key for $app" >&2
        return 1
    end

    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$url/api/v3/command" \
        -H "X-Api-Key: $key" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$api_cmd\"}" 2>/dev/null >/dev/null
        fmt_success "$api_cmd triggered on $app."
    else
        fmt_error "Failed to trigger $api_cmd on $app."
        return 1
    end
end

# cave-backlog-status — Every app wanted/missing backlog
function cave-backlog-status --description 'wanted/missing backlog across every arr app'
    fmt_heading "Backlog Status"
    echo ""
    for app in radarr sonarr
        set -l url (__arr_api_url "$app")
        __arr_api_key "$app" >/dev/null; or continue
        set -l key (__arr_api_key "$app")

        if test "$app" = radarr
            set -l total (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/movie?pageSize=1" -H "X-Api-Key: $key" 2>/dev/null \
                | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("totalRecords", "?"))' 2>/dev/null)
            set -l missing (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/movie?pageSize=1000" -H "X-Api-Key: $key" 2>/dev/null \
                | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d if i.get("monitored") and not i.get("hasFile") and i.get("isAvailable")))' 2>/dev/null)
            echo "  $app: $total monitored, $missing released+missing"
        else
            set -l total (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/series?pageSize=1" -H "X-Api-Key: $key" 2>/dev/null \
                | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("totalRecords", "?"))' 2>/dev/null)
            set -l missing (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/missing?pageSize=1" -H "X-Api-Key: $key" 2>/dev/null \
                | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("totalRecords", "?"))' 2>/dev/null)
            echo "  $app: $total series, $missing aired episodes missing"
        end
    end
end

# cave-command-queue-summary — Backlog across every arr app at once
function cave-command-queue-summary --description 'queued command counts across every arr app'
    fmt_heading "Command Queue Summary"
    echo ""
    for app in radarr sonarr
        set -l url (__arr_api_url "$app")
        __arr_api_key "$app" >/dev/null; or continue
        set -l key (__arr_api_key "$app")
        set -l count (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/command?pageSize=50" -H "X-Api-Key: $key" 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); recs=d.get('records',d) if isinstance(d,dict) else d; print(len([c for c in recs if c.get('status')=='queued']))" 2>/dev/null)
        echo "  $app: $count queued commands"
    end
end

# cave-import-lists <radarr|sonarr> — configured import lists and enabled state
function cave-import-lists --description 'configured import lists and enabled state'
# complete: radarr|sonarr
    if test (count $argv) -ne 1
        echo "Usage: cave-import-lists <radarr|sonarr>" >&2
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
    fmt_heading "$app — Import Lists"
    echo ""

    set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v3/importlist" -H "X-Api-Key: $key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach $app"
        return 1
    end

    echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('records', [])
if not items:
    print('  No import lists configured.')
else:
    for lst in items:
        name = lst.get('name', '?')
        enabled = '✓' if lst.get('enabled') else '✗'
        ltype = lst.get('listType', '?')
        print(f'  [{enabled}] {name} ({ltype})')
" 2>/dev/null
end

# cave-radarr-health — Radarr DB integrity (quality profiles + size)
# Wraps the two preflight scripts so the checks run in one command.
function cave-radarr-health --description 'Radarr DB integrity: quality profiles + DB size'
    fmt_heading "Radarr Health"
    echo ""
    set -l repo "$BEARCAVE_REPO_DIR"

    set -l db "$repo/config/radarr/radarr.db"
    if not test -f "$db"
        echo "  radarr.db  "(fmt_status_dot "missing")"  ($repo/config/radarr/radarr.db)"
        return 1
    end

    # Each guard is read-only; run them in order and summarize.
    python3 "$repo/scripts/check_radarr_profiles.py"
    set -l profiles $status
    python3 "$repo/scripts/check_radarr_db_size.py"
    set -l size $status

    echo ""
    if test "$profiles" -eq 0; and test "$size" -eq 0
        fmt_success "Radarr healthy — profiles and DB size OK."
    else
        fmt_error "Radarr needs attention — see diagnostics above."
    end
end

# cave-radarr-prune [-y|--yes] [--dry-run] — prune radarr.db MediaInfo bloat
# Stops radarr (when running), backs up radarr.db + logs.db, prunes MediaInfo
# blobs and old history, vacuums, and verifies via scripts/prune_radarr_db.py,
# then resumes radarr. Requires an explicit flag — refuses with no args.
function cave-radarr-prune --description 'prune radarr.db MediaInfo bloat (backup, prune, vacuum, verify)'
# complete: -y|--yes|--dry-run
    if test (count $argv) -eq 0
        echo "Usage: cave-radarr-prune [-y|--yes] [--dry-run]" >&2
        return 1
    end
    set -l assume_yes false
    set -l dry_run false
    set -l pargs
    for arg in $argv
        switch $arg
            case -y --yes
                set assume_yes true
            case --dry-run
                set dry_run true
            case -h --help
                echo "Usage: cave-radarr-prune [-y|--yes] [--dry-run]" >&2
                echo "Prune radarr.db bloat: backup, prune, vacuum, verify (see docs/services/radarr.md)." >&2
                return 0
            case '*'
                echo "Unknown option: $arg (usage: cave-radarr-prune [-y|--yes] [--dry-run])" >&2
                return 1
        end
    end

    set -l repo "$BEARCAVE_REPO_DIR"

    set -l db "$repo/config/radarr/radarr.db"
    if not test -f "$db"
        echo "  radarr.db  "(fmt_status_dot "missing")"  ($repo/config/radarr/radarr.db)"
        return 1
    end

    set -l running false
    if type -q docker
        set -l names (docker ps --filter "name=^/radarr" --format '{{.Names}}' 2>/dev/null)
        contains radarr $names; and set running true
    end

    # VACUUM needs an exclusive lock; stop radarr first unless dry-running.
    set -l stopped false
    if test "$running" = true; and test "$dry_run" = false
        if test "$assume_yes" != true
            printf 'Stop radarr while its DB is vacuumed? [y/N] '
            set -l reply
            read -l reply
            switch $reply
                case y Y
                case '*'
                    echo "Aborted."
                    return 1
            end
        end
        fmt_heading "Stopping radarr"
        docker compose -f "$repo/docker-compose.yml" stop radarr
        if test $status -ne 0
            fmt_error "could not stop radarr"
            return 1
        end
        set stopped true
    end

    test "$assume_yes" = true; and set -a pargs --yes
    test "$dry_run" = true; and set -a pargs --dry-run
    python3 "$repo/scripts/prune_radarr_db.py" $pargs
    set -l rc $status

    if test "$stopped" = true
        fmt_heading "Starting radarr"
        docker compose -f "$repo/docker-compose.yml" start radarr >/dev/null 2>&1
        or fmt_warning "radarr did not restart cleanly — run cave-restart-all"
    end

    echo ""
    if test "$rc" -eq 0
        fmt_success "Radarr DB maintenance complete."
    else
        fmt_error "Radarr DB maintenance reported problems (exit $rc)."
    end
    return "$rc"
end

# cave-sonarr-prune [-y|--yes] [--dry-run] — prune sonarr.db MediaInfo bloat
# Sonarr analogue of cave-radarr-prune (AGENTS.md landmine #9, EpisodeFiles
# table): stops sonarr (when running), backs up sonarr.db + logs.db, prunes
# MediaInfo blobs and old history, vacuums, and verifies via
# scripts/prune_sonarr_db.py, then resumes sonarr. Requires an explicit flag —
# refuses with no args.
function cave-sonarr-prune --description 'prune sonarr.db MediaInfo bloat (backup, prune, vacuum, verify)'
# complete: -y|--yes|--dry-run
    if test (count $argv) -eq 0
        echo "Usage: cave-sonarr-prune [-y|--yes] [--dry-run]" >&2
        return 1
    end
    set -l assume_yes false
    set -l dry_run false
    set -l pargs
    for arg in $argv
        switch $arg
            case -y --yes
                set assume_yes true
            case --dry-run
                set dry_run true
            case -h --help
                echo "Usage: cave-sonarr-prune [-y|--yes] [--dry-run]" >&2
                echo "Prune sonarr.db bloat: backup, prune, vacuum, verify (see docs/services/sonarr.md)." >&2
                return 0
            case '*'
                echo "Unknown option: $arg (usage: cave-sonarr-prune [-y|--yes] [--dry-run])" >&2
                return 1
        end
    end

    set -l repo "$BEARCAVE_REPO_DIR"

    set -l db "$repo/config/sonarr/sonarr.db"
    if not test -f "$db"
        echo "  sonarr.db  "(fmt_status_dot "missing")"  ($repo/config/sonarr/sonarr.db)"
        return 1
    end

    set -l running false
    if type -q docker
        set -l names (docker ps --filter "name=^/sonarr" --format '{{.Names}}' 2>/dev/null)
        contains sonarr $names; and set running true
    end

    # VACUUM needs an exclusive lock; stop sonarr first unless dry-running.
    set -l stopped false
    if test "$running" = true; and test "$dry_run" = false
        if test "$assume_yes" != true
            printf 'Stop sonarr while its DB is vacuumed? [y/N] '
            set -l reply
            read -l reply
            switch $reply
                case y Y
                case '*'
                    echo "Aborted."
                    return 1
            end
        end
        fmt_heading "Stopping sonarr"
        docker compose -f "$repo/docker-compose.yml" stop sonarr
        if test $status -ne 0
            fmt_error "could not stop sonarr"
            return 1
        end
        set stopped true
    end

    test "$assume_yes" = true; and set -a pargs --yes
    test "$dry_run" = true; and set -a pargs --dry-run
    python3 "$repo/scripts/prune_sonarr_db.py" $pargs
    set -l rc $status

    if test "$stopped" = true
        fmt_heading "Starting sonarr"
        docker compose -f "$repo/docker-compose.yml" start sonarr >/dev/null 2>&1
        or fmt_warning "sonarr did not restart cleanly — run cave-restart-all"
    end

    echo ""
    if test "$rc" -eq 0
        fmt_success "Sonarr DB maintenance complete."
    else
        fmt_error "Sonarr DB maintenance reported problems (exit $rc)."
    end
    return "$rc"
end

# cave-prowlarr-indexers — Every indexer enabled state + priority
function cave-prowlarr-indexers --description 'Prowlarr indexer enabled state + priority'
    set -l url "$PROWLARR_URL"
    test -n "$url"; or set url "http://localhost:9696"
    set -l key "$PROWLARR_API_KEY"

    fmt_heading "Prowlarr Indexers"
    echo ""

    set -l result (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf "$url/api/v1/indexer" -H "X-Api-Key: $key" 2>/dev/null)
    if test $status -ne 0
        fmt_error "Cannot reach Prowlarr"
        return 1
    end

    echo "$result" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for idx in data:
    name = idx.get('name', '?')
    enabled = '✓' if idx.get('enable') else '✗'
    priority = idx.get('priority', '?')
    print(f'  [{enabled}] {name:<30s} priority={priority}')
" 2>/dev/null
end
