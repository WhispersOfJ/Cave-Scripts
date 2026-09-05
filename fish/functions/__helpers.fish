# ============================================================================
# __helpers.fish — internal helpers for the cave-* functions (fish port)
# ============================================================================
# fish translations of __arr_api, __arr_api_url, __arr_api_key,
# __stack_arr_app, __plex_api, __plex_butler, __seerr_api, __nzbdav_api,
# __stack_containers (same contracts as the bash port).
# Sourced by cave-scripts.fish before the cave-*.fish files.
# ============================================================================

# ----------------------------------------------------------------------------
# API call timeout budgets (per-call type) and the central curl wrapper.
# ----------------------------------------------------------------------------
# Every API call goes through __stack_curl so a wedged service can never hang a
# cave-* command forever. Budgets are seconds; override any of them with the
# matching env var (e.g. STACK_API_TIMEOUT_HEAVY=60) for a slow host.
set -q STACK_API_TIMEOUT_LIGHT; or set -gx STACK_API_TIMEOUT_LIGHT 10
set -q STACK_API_TIMEOUT_MUTATE; or set -gx STACK_API_TIMEOUT_MUTATE 20
set -q STACK_API_TIMEOUT_HEAVY; or set -gx STACK_API_TIMEOUT_HEAVY 30
set -q STACK_DOCKER_TIMEOUT; or set -gx STACK_DOCKER_TIMEOUT 5
# Data transport to embedded python: bulk payloads that scale with library
# size (series maps, history, full-collection pulls) must be piped via stdin
# (echo "$result" | python3 -c ...), never passed through env vars — a single
# env var is capped at 128 KB (MAX_ARG_STRLEN) and can fail execve with E2BIG
# silently. Only scalar config (URLs, keys, IDs, limits) goes via env.

# __stack_curl <budget_secs> <curl args...>
# Wraps curl with --max-time and --connect-timeout so both a wedged accept()
# (no response) and a dead-but-listening port (no connect) fail-soft within
# the budget. On timeout the caller sees curl exit 28 and prints its own
# "Cannot reach" / "timed out" message via the existing status checks.
function __stack_curl --description 'curl with a hard timeout budget (arg 1 = seconds)'
    set -l budget "$argv[1]"
    set -e argv[1]
    command curl --connect-timeout 5 --max-time "$budget" $argv
end

# __arr_api <app> <METHOD> <path> [json_body]
#   app: radarr, sonarr, prowlarr
# Defaults target the host-published ports (host shell: docker service names
# do not resolve). Override with RADARR_URL / SONARR_URL / PROWLARR_URL.
function __arr_api --description 'arr API call: __arr_api <app> <METHOD> <path> [json_body]'
    if test (count $argv) -lt 3
        echo "Usage: __arr_api <app> <METHOD> <path> [json_body]" >&2
        return 1
    end
    set -l app "$argv[1]"
    set -l method "$argv[2]"
    set -l path "$argv[3]"
    set -l body "$argv[4]"
    set -l base_url ""
    set -l api_key ""

    switch $app
        case radarr
            set base_url "$RADARR_URL"
            test -n "$base_url"; or set base_url "http://localhost:7878"
            set api_key "$RADARR_API_KEY"
        case sonarr
            set base_url "$SONARR_URL"
            test -n "$base_url"; or set base_url "http://localhost:8989"
            set api_key "$SONARR_API_KEY"
        case prowlarr
            set base_url "$PROWLARR_URL"
            test -n "$base_url"; or set base_url "http://localhost:9696"
            set api_key "$PROWLARR_API_KEY"
        case '*'
            echo "Unknown app: $app (use radarr, sonarr, or prowlarr)" >&2
            return 1
    end

    # Light GET vs. mutation — pick the budget from the method.
    set -l budget "$STACK_API_TIMEOUT_LIGHT"
    switch $method
        case POST PUT DELETE PATCH
            set budget "$STACK_API_TIMEOUT_MUTATE"
    end

    set -l opts -sS -X "$method" --fail-with-body
    if test -n "$api_key"
        set -a opts -H "X-Api-Key: $api_key"
    end
    if test -n "$body"
        set -a opts -H 'Content-Type: application/json' -d "$body"
    end
    __stack_curl "$budget" $opts "$base_url$path"
end

# __arr_api_url <radarr|sonarr|prowlarr>
function __arr_api_url --description 'base URL for an arr app'
    if test (count $argv) -lt 1
        echo "Usage: __arr_api_url <radarr|sonarr|prowlarr>" >&2
        return 1
    end
    switch $argv[1]
        case radarr
            set -l url "$RADARR_URL"
            test -n "$url"; or set url "http://localhost:7878"
            echo "$url"
        case sonarr
            set -l url "$SONARR_URL"
            test -n "$url"; or set url "http://localhost:8989"
            echo "$url"
        case prowlarr
            set -l url "$PROWLARR_URL"
            test -n "$url"; or set url "http://localhost:9696"
            echo "$url"
        case '*'
            echo "Unknown app: $argv[1] (use radarr, sonarr, or prowlarr)" >&2
            return 1
    end
end

# __arr_api_key <radarr|sonarr|prowlarr> — fails if unset/empty.
function __arr_api_key --description 'API key for an arr app; fails if unset'
    if test (count $argv) -lt 1
        echo "Usage: __arr_api_key <radarr|sonarr|prowlarr>" >&2
        return 1
    end
    set -l key ""
    switch $argv[1]
        case radarr
            set key "$RADARR_API_KEY"
        case sonarr
            set key "$SONARR_API_KEY"
        case prowlarr
            set key "$PROWLARR_API_KEY"
        case '*'
            echo "Unknown app: $argv[1] (use radarr, sonarr, or prowlarr)" >&2
            return 1
    end
    if test -z "$key"
        echo "API key for $argv[1] not set (expected "(string upper -- $argv[1])"_API_KEY uppercase in environment)" >&2
        return 1
    end
    echo "$key"
end

# __stack_arr_app <name> — validate an Arr instance name (radarr or sonarr).
function __stack_arr_app --description 'validate an Arr instance name; prints it, rc 1 otherwise'
    if test (count $argv) -ne 1
        return 1
    end
    switch $argv[1]
        case radarr sonarr
            echo "$argv[1]"
        case '*'
            return 1
    end
end

# __plex_api <METHOD> <path> [json_body]
# Plex runs on host networking: localhost:32400 from the host shell.
function __plex_api --description 'Plex API call: __plex_api <METHOD> <path> [json_body]'
    if test (count $argv) -lt 2
        echo "Usage: __plex_api <METHOD> <path> [json_body]" >&2
        return 1
    end
    set -l method "$argv[1]"
    set -l path "$argv[2]"
    set -l body "$argv[3]"
    set -l base_url "$PLEX_URL"
    test -n "$base_url"; or set base_url "http://localhost:32400"
    set -l budget "$STACK_API_TIMEOUT_LIGHT"
    switch $method
        case POST PUT DELETE PATCH
            set budget "$STACK_API_TIMEOUT_MUTATE"
    end
    set -l opts -sS -X "$method" --fail-with-body -H "Accept: application/json"
    if set -q PLEX_TOKEN[1]; and test -n "$PLEX_TOKEN"
        set -a opts -H "X-Plex-Token: $PLEX_TOKEN"
    end
    if test -n "$body"
        set -a opts -H 'Content-Type: application/json' -d "$body"
    end
    __stack_curl "$budget" $opts "$base_url$path"
end

# __plex_butler <task-name> — trigger a Plex Maintenance (Butler) task.
function __plex_butler --description 'trigger a Plex Butler task'
    set -l task "$argv[1]"
    if test -z "$task"
        echo "Usage: __plex_butler <task-name>" >&2
        return 1
    end
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    if test -z "$PLEX_TOKEN"
        echo "PLEX_TOKEN not set" >&2
        return 1
    end
    if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$plex_url/butler?task=$task&X-Plex-Token=$PLEX_TOKEN" >/dev/null 2>&1
        fmt_success "Butler task '$task' triggered."
    else
        fmt_error "Failed to trigger butler task '$task'."
        return 1
    end
end

# __seerr_api <METHOD> <path> [json_body]
function __seerr_api --description 'Seerr API call: __seerr_api <METHOD> <path> [json_body]'
    if test (count $argv) -lt 2
        echo "Usage: __seerr_api <METHOD> <path> [json_body]" >&2
        return 1
    end
    set -l method "$argv[1]"
    set -l path "$argv[2]"
    set -l body "$argv[3]"
    set -l base_url "$SEERR_URL"
    test -n "$base_url"; or set base_url "http://localhost:5055"
    if test -z "$SEERR_API_KEY"
        echo "SEERR_API_KEY not set" >&2
        return 1
    end
    set -l budget "$STACK_API_TIMEOUT_LIGHT"
    switch $method
        case POST PUT DELETE PATCH
            set budget "$STACK_API_TIMEOUT_MUTATE"
    end
    set -l opts -sS -X "$method" --fail-with-body -H "X-Api-Key: $SEERR_API_KEY"
    if test -n "$body"
        set -a opts -H 'Content-Type: application/json' -d "$body"
    end
    # normalize slashes on both sides (parity with __seerr_api in bash/zsh)
    set base_url (string trim -r -c / -- "$base_url")
    set path (string trim -r -c / -- "$path")
    __stack_curl "$budget" $opts "$base_url/$path"
end

# __nzbdav_api <METHOD> <mode> [extra_params]
# NzbDAV uses SABnzbd-compatible API: /api?mode=<mode>&output=json&apikey=<key>
function __nzbdav_api --description 'NzbDAV API call: __nzbdav_api <METHOD> <mode> [extra_params]'
    if test (count $argv) -lt 2
        echo "Usage: __nzbdav_api <METHOD> <mode> [extra_params]" >&2
        return 1
    end
    set -l method "$argv[1]"
    set -l mode "$argv[2]"
    set -l extra "$argv[3]"
    set -l base_url "$NZBDAV_URL"
    test -n "$base_url"; or set base_url "http://localhost:3000"
    set -l budget "$STACK_API_TIMEOUT_LIGHT"
    switch $method
        case POST PUT DELETE PATCH
            set budget "$STACK_API_TIMEOUT_MUTATE"
    end
    set -l opts -sS -X "$method" --fail-with-body
    set -l query "mode=$mode&output=json"
    if set -q FRONTEND_BACKEND_API_KEY[1]; and test -n "$FRONTEND_BACKEND_API_KEY"
        set query "$query&apikey=$FRONTEND_BACKEND_API_KEY"
    end
    if test -n "$extra"
        set query "$query&$extra"
    end
    __stack_curl "$budget" $opts "$base_url/api?$query"
end

# __stack_containers — live container names (completion helper).
function __stack_containers --description 'all docker container names, sorted'
    # A wedged Docker daemon must not hang tab completion: cap the call and
    # fail soft to an empty list (mirrors the API timeout discipline).
    timeout "$STACK_DOCKER_TIMEOUT" docker ps -a --format '{{.Names}}' 2>/dev/null | sort
end
