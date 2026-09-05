# ============================================================================
# cave-core — core stack commands
# ============================================================================
# desc: core stack status, container, restart, top, version, help commands
# ============================================================================

# cave-status — Show live state/health of every container
function cave-status --description 'Show live state/health of every container'
    fmt_heading "Container Status"
    echo ""
    docker ps -a --format '{{.Names}}\t{{.State}}\t{{.Status}}' | sort | \
    while read -lt tab name st status_line
        printf "  %-25s %s  %s\n" "$name" (fmt_status_dot "$st") "$status_line"
    end
end

# cave-container <restart|stop|start> <name> — control a single container
function cave-container --description 'restart/stop/start a single container'
# complete: <container> restart|stop|start
    if test (count $argv) -ne 2
        echo "Usage: cave-container <restart|stop|start> <name>" >&2
        return 1
    end
    set -l action "$argv[1]"
    set -l name "$argv[2]"
    switch $action
        case restart stop start
            docker "$action" "$name"
        case '*'
            echo "Unknown action: $action (use restart, stop, or start)" >&2
            return 1
    end
end

# cave-restart-all [-y] — restart the whole stack
function cave-restart-all --description 'restart the whole stack (prompts unless -y)'
# complete: -y|--yes
    set -l assume_yes false
    test "$argv[1]" = "-y"; and set assume_yes true
    if test "$assume_yes" != true
        printf "Restart the whole stack? [y/N] "
        set -l reply
        read -l reply
        switch $reply
            case y Y
                set assume_yes true
            case '*'
                echo "Aborted."
                return 1
        end
    end
    fmt_heading "Restarting stack"
    docker compose restart
    fmt_success "Stack restarted."
end

# cave-top — docker stats snapshot
function cave-top --description 'docker stats snapshot'
    fmt_heading "Container Resources"
    echo ""
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
end

# cave-version — repo + compose image versions
function cave-version --description 'repo + compose image versions'
    fmt_heading "Stack Versions"
    set -l repo_line (cd "$BEARCAVE_REPO_DIR"; and git log -1 --format='%h %s' 2>/dev/null; or echo "n/a")
    fmt_kv "repo" "$repo_line"
    set -l docker_line (docker --version 2>/dev/null | cut -d, -f1; or echo "n/a")
    fmt_kv "docker" "$docker_line"
    echo ""
    docker compose images 2>/dev/null; or fmt_warning "docker compose images failed"
end

# cave-help — list all cave-* command categories (from the shared metadata
# parser, one line per category/file — derived from __stack_metadata so help
# can never drift from completions/TUI)
function cave-help --description 'list all cave-* command categories'
    echo "Bear Cave media stack — terminal commands"
    echo ""
    # NB: parse with `cut`, not `read` — tab is IFS whitespace, so read
    # would collapse empty fields (e.g. directive-less functions).
    set -l prev ""
    set -l category ""
    set -l desc ""
    set -l metadata_rows (__stack_metadata)
    for line in $metadata_rows
        test -n "$line"; or continue
        set category (string split -f 2 \t -- "$line")
        set desc (string split -f 3 \t -- "$line")
        test "$category" = "$prev"; and continue
        set prev "$category"
        if test -n "$desc"
            printf "  %-45s %s\n" "$category" "$desc"
        else
            printf "  %s\n" "$category"
        end
    end
end
