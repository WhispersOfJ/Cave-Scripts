# ============================================================================
# cave-core — core stack commands
# ============================================================================
# desc: core stack status, container, restart, top, version, help commands
# ============================================================================

# cave-status — Show live state/health of every container
cave-status() {
    fmt_heading "Container Status"
    echo ""
    docker ps -a --format '{{.Names}}\t{{.State}}\t{{.Status}}' | sort | \
    while IFS=$'\t' read -r name st status_line; do
        printf "  %-25s %s  %s\n" "$name" "$(fmt_status_dot "$st")" "$status_line"
    done
}

# cave-container <restart|stop|start> <name> — control a single container
cave-container() {
# complete: <container> restart|stop|start
    if [ "$#" -ne 2 ]; then
        echo "Usage: cave-container <restart|stop|start> <name>" >&2
        return 1
    fi
    local action="$1" name="$2"
    case "$action" in
        restart|stop|start)
            docker "$action" "$name"
            ;;
        *)
            echo "Unknown action: $action (use restart, stop, or start)" >&2
            return 1
            ;;
    esac
}

# cave-restart-all [-y] — restart the whole stack
cave-restart-all() {
# complete: -y|--yes
    local assume_yes=false
    [ "${1:-}" = "-y" ] && assume_yes=true
    if [ "$assume_yes" != true ]; then
        printf "Restart the whole stack? [y/N] "
        local reply
        read -r reply
        case "$reply" in
            y|Y) assume_yes=true ;;
            *) echo "Aborted."; return 1 ;;
        esac
    fi
    fmt_heading "Restarting stack"
    docker compose restart
    fmt_success "Stack restarted."
}

# cave-top — docker stats snapshot
cave-top() {
    fmt_heading "Container Resources"
    echo ""
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

# cave-version — repo + compose image versions
cave-version() {
    fmt_heading "Stack Versions"
    fmt_kv "repo" "$(cd "$BEARCAVE_REPO_DIR" && git log -1 --format='%h %s' 2>/dev/null || echo 'n/a')"
    fmt_kv "docker" "$(docker --version 2>/dev/null | cut -d, -f1 || echo 'n/a')"
    echo ""
    docker compose images 2>/dev/null || fmt_warning "docker compose images failed"
}

# cave-help — list all stack-* command categories (from the shared metadata
# parser, one line per category/file — same output as before, but derived
# from __stack_metadata so help can never drift from completions/TUI)
cave-help() {
    echo "Bear Cave media stack — terminal commands"
    echo ""
    # NB: parse with `cut`, not `read` — tab is IFS whitespace, so read
    # would collapse empty fields (e.g. directive-less functions).
    local prev="" category desc line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        category="$(cut -f2 <<<"$line")"
        desc="$(cut -f3 <<<"$line")"
        [ "$category" = "$prev" ] && continue
        prev="$category"
        if [ -n "$desc" ]; then
            printf "  %-45s %s\n" "$category" "$desc"
        else
            printf "  %s\n" "$category"
        fi
    done < <(__stack_metadata)
}
