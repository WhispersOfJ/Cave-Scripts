# ============================================================================
# cave-plex-extra — Plex maintenance extras
# ============================================================================
# desc: plex duplicates, gc wrappers, updates, image-clean, analyses
# ============================================================================

# cave-plex-duplicates — show duplicate media in Plex
function cave-plex-duplicates --description 'show duplicate media in Plex'
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"

    fmt_heading "Plex — Duplicates"
    echo ""

    __stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
        | PLEX_URL="$plex_url" TOKEN="$token" python3 -c "
import sys, json, urllib.request, os
try:
    data = json.load(sys.stdin)
    plex_url = os.environ['PLEX_URL']
    token = os.environ['TOKEN']
    for section in data.get('MediaContainer', {}).get('Directory', []):
        key = section.get('key')
        title = section.get('title', '?')
        url = f'{plex_url}/library/sections/{key}/all?X-Plex-Token={token}'
        req = urllib.request.Request(url, headers={'Accept': 'application/json'})
        r = urllib.request.urlopen(req, timeout=10)
        items = json.loads(r.read()).get('MediaContainer', {}).get('Metadata', [])
        dupes = {}
        for item in items:
            name = item.get('title', '?')
            dupes.setdefault(name, []).append(item)
        for name, entries in dupes.items():
            if len(entries) > 1:
                print(f'  {title}: {name} ({len(entries)} copies)')
except Exception as e:
    print(f'  Error: {e}')
" 2>/dev/null
end

# --- thin butler task wrappers -----------------------------------------------

function cave-plex-garbage-collect-media --description 'Plex butler: garbage-collect-media'
# danger: true (deletes media files server-side)
    __plex_butler garbage-collect-media
end

function cave-plex-garbage-collect-blobs --description 'Plex butler: garbage-collect-blobs'
# danger: true (deletes orphaned blob files)
    __plex_butler garbage-collect-blobs
end

function cave-plex-backup-database --description 'Plex butler: backup-database'
    __plex_butler backup-database
end

function cave-plex-automatic-updates --description 'Plex butler: automatic-updates'
# danger: true (installs Plex updates)
    __plex_butler automatic-updates
end

function cave-plex-process-assets --description 'Plex butler: process-assets'
    __plex_butler process-assets
end

function cave-plex-refresh-epg --description 'Plex butler: refresh-epg'
    __plex_butler refresh-epg
end

function cave-plex-refresh-local-media --description 'Plex butler: refresh-local-media'
    __plex_butler refresh-local-media
end

function cave-plex-clean-cache-files --description 'Plex butler: clean-cache-files'
# danger: true (deletes cache files)
    __plex_butler clean-cache-files
end

function cave-plex-clean-log-files --description 'Plex butler: clean-log-files'
# danger: true (deletes log files)
    __plex_butler clean-log-files
end

# cave-plex-image-clean — clean PhotoTranscoder cache, report reclaimed space
function cave-plex-image-clean --description 'clean PhotoTranscoder cache via ImageMaid (run only while Plex is idle)'
    set -l output (docker compose --profile maintenance run --rm --no-deps imagemaid 2>&1)
    set -l rc $status
    set -l recovered (printf '%s\n' "$output" | grep -m1 'Space Recovered:')

    if test $rc -eq 0; and test -n "$recovered"
        printf '%s\n' "$recovered"
    else
        printf '%s\n' "$output" >&2
    end
    return $rc
end

# --- analysis wrappers ---------------------------------------------------------

# cave-plex-deep-media-analysis — deep media analysis on all sections
function cave-plex-deep-media-analysis --description 'deep media analysis on all sections'
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"
    if test -z "$token"
        fmt_error "PLEX_TOKEN not set"
        return 1
    end
    fmt_heading "Plex — Deep Media Analysis"
    echo ""
    set -l sections (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
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
        fmt_success "Deep analysis triggered for $total section(s)."
    else
        fmt_error "Analysis triggered for "(math "$total - $failed")" section(s); $failed failed."
        return 1
    end
end

# cave-plex-upgrade-media-analysis — upgrade media analysis on all sections
function cave-plex-upgrade-media-analysis --description 'upgrade media analysis on all sections'
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"
    if test -z "$token"
        fmt_error "PLEX_TOKEN not set"
        return 1
    end
    fmt_heading "Plex — Upgrade Media Analysis"
    echo ""
    set -l sections (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
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
        fmt_success "Upgrade media analysis triggered for $total section(s)."
    else
        fmt_error "Analysis triggered for "(math "$total - $failed")" section(s); $failed failed."
        return 1
    end
end

# cave-plex-music-analysis — analyze music libraries
function cave-plex-music-analysis --description 'analyze music libraries'
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"
    if test -z "$token"
        fmt_error "PLEX_TOKEN not set"
        return 1
    end
    fmt_heading "Plex — Music Analysis"
    echo ""
    set -l sections (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
        | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", []) if d.get("type")=="artist"]' 2>/dev/null)
    if test -z "$sections"
        fmt_warning "No music libraries found."
        return 0
    end
    set -l failed 0
    set -l total 0
    for key in $sections
        set total (math "$total + 1")
        __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X PUT "$plex_url/library/sections/$key/analyze?X-Plex-Token=$token" >/dev/null 2>&1
        or set failed (math "$failed + 1")
    end
    if test "$failed" -eq 0
        fmt_success "Music analysis triggered for $total section(s)."
    else
        fmt_error "Analysis triggered for "(math "$total - $failed")" section(s); $failed failed."
        return 1
    end
end

# cave-plex-loudness-analysis — loudness analysis on music libraries
function cave-plex-loudness-analysis --description 'loudness analysis on music libraries'
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    set -l token "$PLEX_TOKEN"
    if test -z "$token"
        fmt_error "PLEX_TOKEN not set"
        return 1
    end
    fmt_heading "Plex — Loudness Analysis"
    echo ""
    set -l sections (__stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf -H "Accept: application/json" "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
        | python3 -c 'import sys,json; [print(d["key"]) for d in json.load(sys.stdin)["MediaContainer"].get("Directory", []) if d.get("type")=="artist"]' 2>/dev/null)
    if test -z "$sections"
        fmt_warning "No music libraries found."
        return 0
    end
    set -l failed 0
    set -l total 0
    for key in $sections
        set total (math "$total + 1")
        __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X PUT "$plex_url/library/sections/$key/analyze?X-Plex-Token=$token" >/dev/null 2>&1
        or set failed (math "$failed + 1")
    end
    if test "$failed" -eq 0
        fmt_success "Loudness analysis triggered for $total section(s)."
    else
        fmt_error "Analysis triggered for "(math "$total - $failed")" section(s); $failed failed."
        return 1
    end
end

# cave-plex-generate-media-index — generate media index files
function cave-plex-generate-media-index --description 'Plex butler: generate-media-index'
    __plex_butler generate-media-index
end

# cave-plex-generate-voice-activity — generate voice activity
function cave-plex-generate-voice-activity --description 'Plex butler: generate-voice-activity'
    __plex_butler generate-voice-activity
end

# cave-plex-generate-intro-markers — generate intro markers
function cave-plex-generate-intro-markers --description 'Plex butler: generate-intro-markers'
    __plex_butler generate-intro-markers
end

# cave-plex-generate-credits-markers — generate credits markers
function cave-plex-generate-credits-markers --description 'Plex butler: generate-credits-markers'
    __plex_butler generate-credits-markers
end

# cave-plex-generate-ad-markers — generate ad markers
function cave-plex-generate-ad-markers --description 'Plex butler: generate-ad-markers'
    __plex_butler generate-ad-markers
end

# cave-plex-generate-chapter-thumbs — generate chapter thumbnails
function cave-plex-generate-chapter-thumbs --description 'Plex butler: generate-chapter-thumbs'
    __plex_butler generate-chapter-thumbs
end
