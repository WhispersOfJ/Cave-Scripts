# ============================================================================
# cave-plex-markers — read-only Plex media-marker audit
# ============================================================================
# desc: count delivered Plex intro/credits/ad markers (read-only)
# ============================================================================
# Counts how many media parts carry a delivered intro/credits/ad marker.
# Markers live in each file's metadata (media_parts.extra_data) as JSON under
# pv: keys. Strictly read-only: sqlite3 -readonly, never writes.
function cave-plex-markers --description 'count delivered Plex intro/credits/ad markers (read-only)'
    fmt_heading "Plex Markers"
    echo ""
    set -l repo "$BEARCAVE_REPO_DIR"

    if not type -q sqlite3
        fmt_error "sqlite3 is required but not installed."
        return 1
    end

    set -l db "$repo/config/plex/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    if not test -f "$db"
        echo "  plex library db  "(fmt_status_dot "missing")"  ($db)"
        return 1
    end

    set -l row (sqlite3 -readonly "$db" "
        SELECT COUNT(*),
               SUM(CASE WHEN extra_data LIKE '%pv:intro%' THEN 1 ELSE 0 END),
               SUM(CASE WHEN extra_data LIKE '%pv:credits%' THEN 1 ELSE 0 END),
               SUM(CASE WHEN extra_data LIKE '%pv:ad%' THEN 1 ELSE 0 END)
        FROM media_parts WHERE extra_data IS NOT NULL;
    " 2>/dev/null)
    if test $status -ne 0; or test -z "$row"
        fmt_error "Failed to read marker counts from the Plex library DB."
        return 1
    end

    set -l parts (string split '|' -- "$row")
    set -l total "$parts[1]"
    set -l intro "$parts[2]"
    set -l credits "$parts[3]"
    set -l ad "$parts[4]"

    fmt_kv "analyzed parts" "$total"
    fmt_kv "intro markers" "$intro parts"
    fmt_kv "credits markers" "$credits parts"
    fmt_kv "ad markers" "$ad parts"
    echo ""

    set -l ad_count "$ad"
    test -n "$ad_count"; or set ad_count 0
    if test "$ad_count" -gt 0
        fmt_success "Ad markers present — ad detection is delivering."
    else
        fmt_warning "No ad markers yet — ad detection is on ('all items' + asap), but clean content may legitimately have no ad breaks to detect."
    end
    echo "  read-only audit of $db"
end
