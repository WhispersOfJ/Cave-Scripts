# ============================================================================
# cave-misc.sh — Seerr, notifications, backups, worktree, host checks
# ============================================================================
# desc: seerr requests, notify test, claude backup, worktree, host checks
# ============================================================================

# cave-seerr-requests [pending|approved|available|all]
cave-seerr-requests() {
# complete: pending|approved|available|all
    local status_filter="${1:-pending}"
    __seerr_api GET "api/v1/request?filter=$status_filter"
}

# cave-notify-test — send a test notification via Discord webhook
cave-notify-test() {
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$DISCORD_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d '{"content": "🧪 Test notification from The Bear Cave"}' >/dev/null 2>&1; then
            fmt_success "Test notification sent."
        else
            fmt_error "Failed to send notification."
        fi
    else
        fmt_warning "DISCORD_WEBHOOK_URL not set."
    fi
}

# cave-claude-full-backup — full ~/Claude tree tar.zst backup to Dropbox
cave-claude-full-backup() {
    local dest="$HOME/Dropbox/backups/claude-backup-$(date +%Y%m%d-%H%M%S).tar.zst"
    echo "Backing up ~/Claude to $dest..."
    mkdir -p "$(dirname "$dest")"
    tar -cf - -C "$HOME" Claude | zstd -o "$dest"
    echo "Done: $dest"
}

# cave-worktree <task-branch>
# Creates a task-named git worktree and branch per the AGENTS.md Worktree
# Discipline: one worktree per task, named by the task, branched off
# origin/main, with the main checkout left clean.
cave-worktree() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: cave-worktree <task-branch>  e.g. cave-worktree docs/foo" >&2
        return 1
    fi
    local branch="$1"

    # Task names are lowercase and dash-separated, optionally type-prefixed
    # (docs/foo, fix-bar, ci/quality-always-run, ...).
    if ! [[ "$branch" =~ ^[a-z][a-z0-9-]*(/[a-z][a-z0-9-]*)?$ ]]; then
        fmt_error "Invalid task name '$branch' (use e.g. docs/foo or fix-bar)"
        return 1
    fi

    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [ -z "$repo_root" ]; then
        fmt_error "Not inside the repository"
        return 1
    fi

    if git show-ref --verify --quiet "refs/heads/$branch"; then
        fmt_error "Branch '$branch' already exists locally; delete it or pick a different task name"
        return 1
    fi

    # A twin attempt may exist on the remote only — pushed but unmerged, or
    # a stale branch from an earlier run. Refuse rather than fork a second
    # branch with the same name.
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        fmt_error "Branch '$branch' already exists on origin (stale or in-flight); delete it or pick a different task name"
        return 1
    fi

    local slug="${branch##*/}"
    local wt_path
    wt_path="$(dirname "$repo_root")/wt-$slug"

    # A deleted worktree directory can leave a stale registration behind;
    # `test -e` misses it and `git worktree add` then fails cryptically.
    # Refuse and point at the one-line fix.
    if git worktree list --porcelain | grep -q "^worktree $wt_path$"; then
        fmt_error "Worktree '$wt_path' is registered but missing on disk; run 'git worktree prune' and retry"
        return 1
    fi

    if [ -e "$wt_path" ]; then
        fmt_error "Worktree path '$wt_path' already exists"
        return 1
    fi

    git fetch -q origin main 2>/dev/null
    if ! git worktree add -b "$branch" "$wt_path" origin/main; then
        fmt_error "Failed to create worktree (is origin/main available?)"
        return 1
    fi

    cd "$wt_path" || return 1
    fmt_success "Worktree ready: branch $branch at $wt_path"
}

# cave-image-check — show Docker image versions
cave-image-check() {
    fmt_heading "Docker Image Versions"
    echo ""
    docker ps --format '{{.Names}}\t{{.Image}}' | sort | \
    while IFS=$'\t' read -r name image; do
        echo "  $name  $image"
    done
}

# cave-perms-check — check file permissions on config directories
cave-perms-check() {
    fmt_heading "Permissions Check"
    echo ""
    local repo="$BEARCAVE_REPO_DIR"
    local found=0 d f
    for d in "$repo/config" "$repo/secrets"; do
        if [ -d "$d" ]; then
            # List unreadable files (mirrors `find ! -readable`)
            while IFS= read -r -d '' f; do
                if [ ! -r "$f" ]; then
                    found=1
                    echo "  $f"
                fi
            done < <(find "$d" -print0 2>/dev/null | head -z -n 21)
        else
            echo "  $d  $(fmt_status_dot "missing")"
        fi
    done
    if [ "$found" -eq 0 ]; then
        fmt_success "All config files are readable."
    fi
}

# cave-oom-check — check for OOM-killed containers
cave-oom-check() {
    fmt_heading "OOM Check"
    echo ""
    local found=0 c oom
    while IFS= read -r c; do
        [ -z "$c" ] && continue
        oom="$(docker inspect --format '{{.State.OOMKilled}}' "$c" 2>/dev/null)"
        if [ "$oom" = "true" ]; then
            found=1
            echo "  $(fmt_status_dot "OOM-killed")  $c"
        fi
    done < <(docker ps -a --format '{{.Names}}')
    if [ "$found" -eq 0 ]; then
        fmt_success "No OOM-killed containers."
    fi
}

# cave-resource-check — check containers missing mem_limit/cpus
cave-resource-check() {
    fmt_heading "Resource Check"
    echo ""
    local found=0 c mem cpus mem_ok cpu_ok
    while IFS= read -r c; do
        [ -z "$c" ] && continue
        mem="$(docker inspect --format '{{.HostConfig.Memory}}' "$c" 2>/dev/null)"
        cpus="$(docker inspect --format '{{.HostConfig.NanoCpus}}' "$c" 2>/dev/null)"
        mem_ok="✗"
        cpu_ok="✗"
        if [ -n "$mem" ] && [ "$mem" != "0" ]; then
            mem_ok="✓"
        fi
        if [ -n "$cpus" ] && [ "$cpus" != "0" ]; then
            cpu_ok="✓"
        fi
        if [ "$mem_ok" = "✗" ] || [ "$cpu_ok" = "✗" ]; then
            found=1
            echo "  $c  mem=$mem_ok  cpus=$cpu_ok"
        fi
    done < <(docker ps --format '{{.Names}}')
    if [ "$found" -eq 0 ]; then
        fmt_success "All containers have resource limits set."
    fi
}

# cave-log-levels — show (read-only) log levels for services
cave-log-levels() {
    if [ "$#" -eq 0 ]; then
        fmt_heading "Log Levels"
        echo ""
        local app level
        for app in prowlarr radarr sonarr; do
            level="$(docker exec "$app" cat /config/Logging/Levels.json 2>/dev/null \
                | grep -oP '"[^"]+"\s*:\s*"[^"]+"' | head -3)"
            if [ -n "$level" ]; then
                echo "  $app:"
                echo "$level" | while IFS= read -r l; do
                    echo "    $l"
                done
            else
                echo "  $app: default"
            fi
        done
    else
        echo "Usage: cave-log-levels (read-only — set via Arr web UI)" >&2
        return 1
    fi
}
