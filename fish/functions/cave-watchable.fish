# ============================================================================
# cave-watchable — "What's watchable tonight" (TODO.md #6)
# ============================================================================
# desc: watchable tonight, recently added, unwatched, request status
# ============================================================================
# Read-only views over the existing host-published APIs. Nothing here
# mutates the stack: every collector calls the same __stack_curl /
# __arr_api / __seerr_api helpers the other cave-* commands use, with the
# LIGHT timeout budget, and every renderer degrades to a clear per-source
# error line when a service is unreachable — a wedged service dims one
# section, never the whole view (the anti-dashboard contract: thin,
# read-only, no container, no state).
#
# NOTE on the embedded python: it lives inside fish single-quoted strings
# where possible, or inside double-quoted command substitutions with
# %-formatting only (never nested double-quoted f-strings — the \"
# escaping inside "..." python is fragile across shell -> python quoting).
#
# Seerr status ladder (verified against seerr-team/seerr
# server/constants/media.ts, 2026-09-03):
#   request status: 1 PENDING, 2 APPROVED, 3 DECLINED, 4 FAILED,
#                   5 COMPLETED — open pipeline is 1|2 only
#   media status:   1 UNKNOWN, 2 PENDING, 3 PROCESSING,
#                   4 PARTIALLY_AVAILABLE, 5 AVAILABLE, 6 BLOCKLISTED,
#                   7 DELETED
#
# cave-watchable          the whole picture, one screen
# cave-unwatched [limit]  unwatched Plex content, newest first
# cave-recent [limit]     recently added in the *arr apps
# cave-requests [take]    Seerr request status (the what's-coming view)
# ============================================================================

# --- shared helpers ----------------------------------------------------------

# __watchable_seerr_key — resolve the Seerr API key or emit an error line.
function __watchable_seerr_key --description 'resolve the Seerr API key or emit an error line'
    if test -n "$SEERR_API_KEY"
        echo "$SEERR_API_KEY"
        return 0
    end
    echo "SEERR_API_KEY not set" >&2
    return 1
end

function __watchable_plex_token --description 'resolve the Plex token or emit an error line'
    if test -n "$PLEX_TOKEN"
        echo "$PLEX_TOKEN"
        return 0
    end
    echo "PLEX_TOKEN not set" >&2
    return 1
end

# __watchable_plex_sections <token> — echo "key|title|type" per library.
function __watchable_plex_sections --description 'echo key|title|type per Plex library'
    set -l token "$argv[1]"
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"
    __stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf \
        -H "Accept: application/json" \
        "$plex_url/library/sections?X-Plex-Token=$token" 2>/dev/null \
        | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    for s in d["MediaContainer"].get("Directory", []):
        print("%s|%s|%s" % (s["key"], s["title"], s["type"]))
except Exception:
    pass
'
end

# --- cave-watchable -----------------------------------------------------------

# cave-watchable — one-screen "what's watchable tonight" summary
function cave-watchable --description "one-screen what's-watchable-tonight summary"
    fmt_heading "What's watchable tonight"
    echo ""

    # --- Seerr: what's coming (open requests) ---
    cave-requests 5; or true

    # --- Plex: unwatched, newest first ---
    echo ""
    cave-unwatched 10; or true

    # --- *arr: recently added ---
    echo ""
    cave-recent 5; or true
end

# --- cave-unwatched -----------------------------------------------------------

# cave-unwatched [limit] — unwatched Plex content, newest first
function cave-unwatched --description 'unwatched Plex content, newest first'
# complete: <limit>
    set -l limit "$argv[1]"
    test -n "$limit"; or set limit 10
    set -l token (__watchable_plex_token)
    if test $status -ne 0
        fmt_error "Cannot read Plex: PLEX_TOKEN not set"
        return 1
    end
    set -l plex_url "$PLEX_URL"
    test -n "$plex_url"; or set plex_url "http://localhost:32400"

    fmt_heading "Unwatched (Plex, newest first)"
    echo ""

    set -l sections (__watchable_plex_sections "$token")
    if test -z "$sections"
        fmt_error "Cannot reach Plex at $plex_url"
        return 1
    end

    set -l any 0
    set -l section_rows (string split \n -- "$sections")
    for row in $section_rows
        set -l parts (string split '|' -- "$row")
        set -l key "$parts[1]"
        set -l title "$parts[2]"
        set -l type "$parts[3]"
        test -n "$key"; or continue
        # movie/show sections only (skip artist/photo libraries if any)
        switch $type
            case movie show
            case '*'
                continue
        end
        set any 1
        echo "  [$title]"
        __stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf \
            -H "Accept: application/json" \
            "$plex_url/library/sections/$key/unwatched?sort=addedAt:desc&X-Plex-Token=$token" 2>/dev/null \
            | LIMIT="$limit" python3 -c '
import sys, json, os, time
try:
    items = json.load(sys.stdin)["MediaContainer"].get("Metadata", [])
except Exception:
    items = []
limit = int(os.environ.get("LIMIT", "10"))
now = int(time.time())
fresh = [v for v in items if now - v.get("addedAt", 0) <= 30 * 86400]
for v in fresh[:limit]:
    age = (now - v.get("addedAt", 0)) // 86400
    print("  %s (%s) - added %dd ago" % (v.get("title", "?"), v.get("year", "?"), age))
if not fresh:
    print("  nothing added in the last 30 days")
elif len(fresh) > limit:
    print("  ... and %d more recent" % (len(fresh) - limit))
print("  (%d of %d unwatched added within the last 30 days)" % (len(fresh), len(items)))
'
        echo ""
    end
    test "$any" -eq 1; or fmt_warning "No movie/show libraries found."
end

# --- cave-recent ---------------------------------------------------------------

# cave-recent [limit] — recently added in the *arr apps
function cave-recent --description 'recently added in the *arr apps'
# complete: <limit>
    set -l limit "$argv[1]"
    test -n "$limit"; or set limit 5

    fmt_heading "Recently added"
    echo ""

    # Radarr: newest movies by added date. HEAVY budget: /api/v3/movie is a
    # full-table render even with pageSize=1 (~10-14s on the current bloated
    # radarr.db; LIGHT's 10s times out — measured 2026-09-03).
    set -l rurl (__arr_api_url radarr 2>/dev/null)
    set -l rkey (__arr_api_key radarr 2>/dev/null)
    if test $status -eq 0; and test -n "$rkey"
        __stack_curl "$STACK_API_TIMEOUT_HEAVY" -sf \
            "$rurl/api/v3/movie?sortKey=added&order=desc&pageSize=$limit" \
            -H "X-Api-Key: $rkey" 2>/dev/null | LIMIT="$limit" python3 -c '
import sys, json, os
limit = int(os.environ.get("LIMIT", "5"))
try:
    items = json.load(sys.stdin)
except Exception:
    items = []
print("  [radarr]")
if not items:
    print("  (unreachable or empty)")
for m in items[:limit]:
    added = (m.get("added") or "")[:10]
    print("  %s (%s) - added %s" % (m.get("title", "?"), m.get("year", "?"), added))
'
    else
        echo "  [radarr]"
        echo "  (RADARR_API_KEY not set)"
    end
    echo ""

    # Sonarr: newest series by added date
    set -l surl (__arr_api_url sonarr 2>/dev/null)
    set -l skey (__arr_api_key sonarr 2>/dev/null)
    if test $status -eq 0; and test -n "$skey"
        __stack_curl "$STACK_API_TIMEOUT_LIGHT" -sf \
            "$surl/api/v3/series?sortKey=added&order=desc&pageSize=$limit" \
            -H "X-Api-Key: $skey" 2>/dev/null | LIMIT="$limit" python3 -c '
import sys, json, os
limit = int(os.environ.get("LIMIT", "5"))
try:
    items = json.load(sys.stdin)
except Exception:
    items = []
print("  [sonarr]")
if not items:
    print("  (unreachable or empty)")
for s in items[:limit]:
    added = (s.get("added") or "")[:10]
    print("  %s (%s) - added %s" % (s.get("title", "?"), s.get("year", "?"), added))
'
    else
        echo "  [sonarr]"
        echo "  (SONARR_API_KEY not set)"
    end
    echo ""
end

# --- cave-requests ---------------------------------------------------------------

# cave-requests [take] — Seerr request status (the what's-coming view)
function cave-requests --description "Seerr request status (the what's-coming view)"
# complete: <take>
    set -l take "$argv[1]"
    test -n "$take"; or set take 10
    set -l key (__watchable_seerr_key)
    if test $status -ne 0
        fmt_error "Cannot read Seerr: SEERR_API_KEY not set"
        return 1
    end

    fmt_heading "Requests (Seerr)"
    echo ""

    set -l counts (__seerr_api GET "api/v1/request/count" 2>/dev/null)
    if test -z "$counts"
        fmt_error "Cannot reach Seerr"
        return 1
    end

    echo "$counts" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print("  total=%s pending=%s approved=%s declined=%s failed=%s processing=%s available=%s completed=%s"
          % (d.get("total", "?"), d.get("pending", "?"), d.get("approved", "?"),
             d.get("declined", "?"), d.get("failed", "?"), d.get("processing", "?"),
             d.get("available", "?"), d.get("completed", "?")))
except Exception:
    print("  (unreadable count response)")
'

    # Open requests only (PENDING=1, APPROVED=2) — declined/failed/completed
    # are the closed set and never appear. The media state is the "what's
    # coming" signal: a request can be approved while its media is already on
    # Plex (state 5) — surface that as watchable-now, not still-coming.
    __seerr_api GET "api/v1/request?take=$take&skip=0" 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
results = d.get("results", []) or []
open_statuses = {1, 2}  # PENDING, APPROVED
media_labels = {1: "unknown", 2: "pending", 3: "processing",
                4: "partially available", 5: "available",
                6: "blocklisted", 7: "deleted"}
shown = 0
for r in results:
    if r.get("status") not in open_statuses:
        continue
    m = r.get("media") or {}
    title = m.get("title")
    if not title:
        if m.get("tmdbId"):
            title = "tmdb:%s" % m.get("tmdbId")
        elif m.get("tvdbId"):
            title = "tvdb:%s" % m.get("tvdbId")
        else:
            title = "?"
    who = ((r.get("requestedBy") or {}).get("plexUsername")) or \
          ((r.get("requestedBy") or {}).get("displayName")) or "unknown"
    kind = r.get("type", "?")
    mst = m.get("status")
    if mst == 5:
        print("  [%s] %s - by %s (available now)" % (kind, title, who))
    else:
        print("  [%s] %s - by %s (%s)" % (kind, title, who,
              media_labels.get(mst, str(mst or "?"))))
    shown += 1
if shown == 0:
    print("  no open requests")
'
end
