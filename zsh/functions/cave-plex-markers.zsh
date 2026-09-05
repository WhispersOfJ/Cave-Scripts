# ============================================================================
# cave-plex-markers — read-only Plex media-marker audit
# ============================================================================
# desc: count delivered Plex intro/credits/ad markers (read-only)
# ============================================================================
# Counts how many media parts carry a delivered intro/credits/ad marker.
# Markers live in each file's metadata (media_parts.extra_data) as JSON under
# pv: keys. Strictly read-only: sqlite3 -readonly, never writes.
cave-plex-markers() {
    fmt_heading "Plex Markers"
    echo ""
    local repo="$BEARCAVE_REPO_DIR"
    if [ -z "$repo" ]; then
        local self="${(%):-%x}"
        local real
        real="$(readlink -f "$self" 2>/dev/null || echo "$self")"
        repo="$(dirname "$(dirname "$(dirname "$(dirname "$real")")")")"
    fi

    if ! command -v sqlite3 >/dev/null 2>&1; then
        fmt_error "sqlite3 is required but not installed."
        return 1
    fi

    local db="$repo/config/plex/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"
    if [ ! -f "$db" ]; then
        echo "  plex library db  $(fmt_status_dot "missing")  ($db)"
        return 1
    fi

    local row
    row="$(sqlite3 -readonly "$db" "
        SELECT COUNT(*),
               SUM(CASE WHEN extra_data LIKE '%pv:intro%' THEN 1 ELSE 0 END),
               SUM(CASE WHEN extra_data LIKE '%pv:credits%' THEN 1 ELSE 0 END),
               SUM(CASE WHEN extra_data LIKE '%pv:ad%' THEN 1 ELSE 0 END)
        FROM media_parts WHERE extra_data IS NOT NULL;
    " 2>/dev/null)"
    if [ $? -ne 0 ] || [ -z "$row" ]; then
        fmt_error "Failed to read marker counts from the Plex library DB."
        return 1
    fi

    IFS='|' read -r total intro credits ad <<< "$row"

    fmt_kv "analyzed parts" "$total"
    fmt_kv "intro markers" "$intro parts"
    fmt_kv "credits markers" "$credits parts"
    fmt_kv "ad markers" "$ad parts"
    echo ""

    if [ "${ad:-0}" -gt 0 ]; then
        fmt_success "Ad markers present — ad detection is delivering."
    else
        fmt_warning "No ad markers yet — ad detection is on ('all items' + asap), but clean content may legitimately have no ad breaks to detect."
    fi
    echo "  read-only audit of $db"
}
