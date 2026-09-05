# ============================================================================
# cave-misc — Seerr, notifications, backups, worktree, host checks
# ============================================================================
# desc: seerr requests, notify test, claude backup, worktree, host checks
# ============================================================================

# cave-seerr-requests [pending|approved|available|all]
function cave-seerr-requests --description 'Seerr request list (filter: pending|approved|available|all)'
# complete: pending|approved|available|all
    set -l status_filter "$argv[1]"
    test -n "$status_filter"; or set status_filter pending
    __seerr_api GET "api/v1/request?filter=$status_filter"
end

# cave-notify-test — send a test notification via Discord webhook
function cave-notify-test --description 'send a test notification via Discord webhook'
    if test -n "$DISCORD_WEBHOOK_URL"
        if __stack_curl "$STACK_API_TIMEOUT_MUTATE" -sf -X POST "$DISCORD_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d '{"content": "🧪 Test notification from The Bear Cave"}' >/dev/null 2>&1
            fmt_success "Test notification sent."
        else
            fmt_error "Failed to send notification."
        end
    else
        fmt_warning "DISCORD_WEBHOOK_URL not set."
    end
end

# cave-claude-full-backup — full ~/Claude tree tar.zst backup to Dropbox
function cave-claude-full-backup --description 'full ~/Claude tree tar.zst backup to Dropbox'
    set -l dest "$HOME/Dropbox/backups/claude-backup-(date +%Y%m%d-%H%M%S).tar.zst"
    set dest (string replace -a '(date +%Y%m%d-%H%M%S)' (date +%Y%m%d-%H%M%S) -- "$dest")
    echo "Backing up ~/Claude to $dest..."
    mkdir -p (dirname "$dest")
    tar -cf - -C "$HOME" Claude | zstd -o "$dest"
    echo "Done: $dest"
end

# cave-worktree <task-branch>
# Creates a task-named git worktree and branch per the AGENTS.md Worktree
# Discipline: one worktree per task, named by the task, branched off
# origin/main, with the main checkout left clean.
function cave-worktree --description 'create a task-named git worktree + branch off origin/main'
    if test (count $argv) -ne 1
        echo "Usage: cave-worktree <task-branch>  e.g. cave-worktree docs/foo" >&2
        return 1
    end
    set -l branch "$argv[1]"

    # Task names are lowercase and dash-separated, optionally type-prefixed
    # (docs/foo, fix-bar, ci/quality-always-run, ...).
    if not string match -qr '^[a-z][a-z0-9-]*(/[a-z][a-z0-9-]*)?$' -- "$branch"
        fmt_error "Invalid task name '$branch' (use e.g. docs/foo or fix-bar)"
        return 1
    end

    set -l repo_root (git rev-parse --show-toplevel 2>/dev/null)
    if test -z "$repo_root"
        fmt_error "Not inside the repository"
        return 1
    end

    if git show-ref --verify --quiet "refs/heads/$branch"
        fmt_error "Branch '$branch' already exists locally; delete it or pick a different task name"
        return 1
    end

    # A twin attempt may exist on the remote only — pushed but unmerged, or
    # a stale branch from an earlier run. Refuse rather than fork a second
    # branch with the same name.
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"
        fmt_error "Branch '$branch' already exists on origin (stale or in-flight); delete it or pick a different task name"
        return 1
    end

    set -l slug (string split -r -m 1 '/' -- "$branch")[-1]
    set -l wt_path (dirname "$repo_root")/wt-$slug

    # A deleted worktree directory can leave a stale registration behind;
    # `test -e` misses it and `git worktree add` then fails cryptically.
    # Refuse and point at the one-line fix.
    if git worktree list --porcelain | grep -q "^worktree $wt_path\$"
        fmt_error "Worktree '$wt_path' is registered but missing on disk; run 'git worktree prune' and retry"
        return 1
    end

    if test -e "$wt_path"
        fmt_error "Worktree path '$wt_path' already exists"
        return 1
    end

    git fetch -q origin main 2>/dev/null
    if not git worktree add -b "$branch" "$wt_path" origin/main
        fmt_error "Failed to create worktree (is origin/main available?)"
        return 1
    end

    cd "$wt_path"; or return 1
    fmt_success "Worktree ready: branch $branch at $wt_path"
end

# cave-image-check — show Docker image versions
function cave-image-check --description 'show Docker image versions'
    fmt_heading "Docker Image Versions"
    echo ""
    docker ps --format '{{.Names}}\t{{.Image}}' | sort | \
    while read -lt tab name image
        echo "  $name  $image"
    end
end

# cave-perms-check — check file permissions on config directories
function cave-perms-check --description 'check file permissions on config directories'
    fmt_heading "Permissions Check"
    echo ""
    set -l repo "$BEARCAVE_REPO_DIR"
    set -l found 0
    for d in "$repo/config" "$repo/secrets"
        if test -d "$d"
            # List unreadable files (mirrors `find ! -readable`)
            for f in (find "$d" -print0 2>/dev/null | head -z -n 21 | string split0)
                if not test -r "$f"
                    set found 1
                    echo "  $f"
                end
            end
        else
            echo "  $d  "(fmt_status_dot "missing")
        end
    end
    if test "$found" -eq 0
        fmt_success "All config files are readable."
    end
end

# cave-oom-check — check for OOM-killed containers
function cave-oom-check --description 'check for OOM-killed containers'
    fmt_heading "OOM Check"
    echo ""
    set -l found 0
    for c in (docker ps -a --format '{{.Names}}')
        test -z "$c"; and continue
        set -l oom (docker inspect --format '{{.State.OOMKilled}}' "$c" 2>/dev/null)
        if test "$oom" = "true"
            set found 1
            echo "  "(fmt_status_dot "OOM-killed")"  $c"
        end
    end
    if test "$found" -eq 0
        fmt_success "No OOM-killed containers."
    end
end

# cave-resource-check — check containers missing mem_limit/cpus
function cave-resource-check --description 'check containers missing mem_limit/cpus'
    fmt_heading "Resource Check"
    echo ""
    set -l found 0
    for c in (docker ps --format '{{.Names}}')
        test -z "$c"; and continue
        set -l mem (docker inspect --format '{{.HostConfig.Memory}}' "$c" 2>/dev/null)
        set -l cpus (docker inspect --format '{{.HostConfig.NanoCpus}}' "$c" 2>/dev/null)
        set -l mem_ok "✗"
        set -l cpu_ok "✗"
        if test -n "$mem"; and test "$mem" != "0"
            set mem_ok "✓"
        end
        if test -n "$cpus"; and test "$cpus" != "0"
            set cpu_ok "✓"
        end
        if test "$mem_ok" = "✗"; or test "$cpu_ok" = "✗"
            set found 1
            echo "  $c  mem=$mem_ok  cpus=$cpu_ok"
        end
    end
    if test "$found" -eq 0
        fmt_success "All containers have resource limits set."
    end
end

# cave-log-levels — show (read-only) log levels for services
function cave-log-levels --description 'show (read-only) log levels for services'
    if test (count $argv) -eq 0
        fmt_heading "Log Levels"
        echo ""
        for app in prowlarr radarr sonarr
            set -l level (docker exec "$app" cat /config/Logging/Levels.json 2>/dev/null \
                | grep -oP '"[^"]+"\s*:\s*"[^"]+"' | head -3)
            if test -n "$level"
                echo "  $app:"
                for l in $level
                    echo "    $l"
                end
            else
                echo "  $app: default"
            end
        end
    else
        echo "Usage: cave-log-levels (read-only — set via Arr web UI)" >&2
        return 1
    end
end
