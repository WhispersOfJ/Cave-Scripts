# ============================================================================
# cave-maintenance — maintenance-verification digest
# ============================================================================
# desc: nightly maintenance digest — reclaim log, timers, dotfiles, DBs, queue
# ============================================================================

# cave-maintenance-digest — verify the nightly maintenance actually ran
# Prints one line per maintenance surface: the 04:00 disk-reclaim log
# freshness, failed user timers, dotfiles push state, Radarr/Sonarr DB
# health, and the nzbdav queue. Exit 0 when all checks pass (soft warnings
# allowed); exit 1 when something FAILs. Backed by
# scripts/maintenance_digest.py (TODO.md project #1). Read-only — safe to
# run any time; designed for a morning cron after the 04:00 reclaim.
function cave-maintenance-digest --description 'verify the nightly maintenance actually ran'
    if test (count $argv) -gt 0; and test "$argv[1]" = "-h" -o "$argv[1]" = "--help"
        echo "Usage: cave-maintenance-digest" >&2
        echo "Verify nightly maintenance ran: reclaim log, timers, dotfiles, DBs, queue." >&2
        return 0
    end
    if test (count $argv) -ne 0
        echo "Usage: cave-maintenance-digest (no arguments)" >&2
        return 1
    end

    set -l repo "$BEARCAVE_REPO_DIR"

    # --repo makes config/ DB paths resolve against the *operational*
    # checkout (the one holding config/radarr + config/sonarr and .env),
    # even when the loader itself was sourced from a worktree clone.
    python3 "$repo/scripts/maintenance_digest.py" --repo "$repo"
end

# cave-audit-residue — retired-service/path residue audit
# Scans compose, .env.template, workflows, functions, docs filenames,
# crontab, and user timers for references to retired services and dead
# project paths — the automated exhaustive-removal checklist (AGENTS.md
# landmine #7, TODO.md project #2). Backed by scripts/audit_residue.py, whose
# registry mirrors docs/services/lifecycle.md. Read-only — safe to run any
# time. Exit 0 = no residue; 1 = residue found (host units print per-unit).
function cave-audit-residue --description 'retired-service/path residue audit'
    if test (count $argv) -gt 0; and test "$argv[1]" = "-h" -o "$argv[1]" = "--help"
        echo "Usage: cave-audit-residue" >&2
        echo "Scan for retired-service and dead-path residue (repo + host units/crontab)." >&2
        return 0
    end
    if test (count $argv) -ne 0
        echo "Usage: cave-audit-residue (no arguments)" >&2
        return 1
    end

    set -l repo "$BEARCAVE_REPO_DIR"

    python3 "$repo/scripts/audit_residue.py"
end

# cave-config-drift — running-container images vs compose pins
# Surfaces containers whose running image differs from the compose pin
# (unpackerr 0.15.2 running vs v0.16.1 pinned; plex on an older digest
# than the @sha256 pin — both found manually 2026-09-02). Backed by
# scripts/check_config_drift.py; `docker compose config` is the pin source
# of truth, `docker inspect` the running state. Read-only — safe to run
# any time. Exit 0 = every running service matches its pin; 1 = drift.
function cave-config-drift --description 'running-container images vs compose pins'
    if test (count $argv) -gt 0; and test "$argv[1]" = "-h" -o "$argv[1]" = "--help"
        echo "Usage: cave-config-drift" >&2
        echo "Report containers whose running image differs from their compose pin." >&2
        return 0
    end
    if test (count $argv) -ne 0
        echo "Usage: cave-config-drift (no arguments)" >&2
        return 1
    end

    set -l repo "$BEARCAVE_REPO_DIR"

    python3 "$repo/scripts/check_config_drift.py"
end
