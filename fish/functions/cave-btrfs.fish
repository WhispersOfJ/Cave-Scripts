# ============================================================================
# cave-btrfs — btrfs filesystem info & maintenance (M3, spec §6.4/§7)
# ============================================================================
# desc: btrfs usage, subvolumes, device stats, scrub/balance, snapper commands
# ============================================================================
#
# Safety shape of this family (spec/functions.yaml):
#   read-only            usage/subvolumes/device-stats/scrub-status/
#                        balance-status/qgroup/snapper list|status|diff
#   mutating-safe        snapshot create|delete, subvol create (confirm+--yes)
#   destructive-confirm  scrub start, balance start (--yes + confirm)
#
# All privileged probes go through __btrfs_run (sudo -n when available, a
# clear refusal otherwise). Mutations always echo the exact command before
# executing it (echo-before-exec) and honor CAVE_BTRFS_DRYRUN=1 to print
# without executing — that is also what the offline suites assert against.
# Scrub/balance always target the filesystem root `/`; there is no path
# argument, so `/boot` is structurally out of reach (plan M3 task 3).

function __btrfs_run
    if sudo -n true >/dev/null 2>&1
        sudo -n $argv
    else
        echo "cave-btrfs: '$argv' needs root (passwordless sudo unavailable)" >&2
        return 1
    end
end

function __btrfs_exec_or_print
    echo "+ $argv"
    if test "$CAVE_BTRFS_DRYRUN" = "1"
        return 0
    end
    $argv
end

function __btrfs_confirm
    if test "$CAVE_BTRFS_DRYRUN" = "1"
        return 0
    end
    printf '%s? [y/N] ' "$argv[1]"
    read -l reply
    switch $reply
        case y Y
            return 0
        case '*'
            echo "Aborted."
            return 1
    end
end

# cave-btrfs-usage — filesystem usage by class (unprivileged)
function cave-btrfs-usage
    fmt_heading "Btrfs Usage"
    echo ""
    if not btrfs filesystem df / 2>/dev/null
        echo "btrfs filesystem df unavailable — falling back to df:"
        df -h /
    end
end

# cave-btrfs-subvolumes — subvolume layout of the fs root
function cave-btrfs-subvolumes
    fmt_heading "Btrfs Subvolumes"
    echo ""
    if sudo -n true >/dev/null 2>&1
        sudo -n btrfs subvolume list / 2>/dev/null; or echo "subvolume list failed"
    else
        echo "(passwordless sudo unavailable — showing mount-level layout)"
        findmnt -t btrfs -o TARGET,SOURCE,OPTIONS
    end
end

# cave-btrfs-device-stats — per-device error counters
function cave-btrfs-device-stats
    fmt_heading "Btrfs Device Stats"
    echo ""
    __btrfs_run btrfs device stats /
end

# cave-btrfs-scrub-status — scrub state (idle or running)
function cave-btrfs-scrub-status
    fmt_heading "Btrfs Scrub Status"
    echo ""
    __btrfs_run btrfs scrub status /
end

# cave-btrfs-balance-status — balance state (none or in progress)
function cave-btrfs-balance-status
    fmt_heading "Btrfs Balance Status"
    echo ""
    __btrfs_run btrfs balance status /
end

# cave-btrfs-qgroup — quota groups (graceful when quotas are disabled)
function cave-btrfs-qgroup
    fmt_heading "Btrfs Qgroups"
    echo ""
    if not __btrfs_run btrfs qgroup show / 2>/dev/null
        echo "quota group support is disabled on this filesystem"
        return 0
    end
end

# cave-btrfs-snapshot list | create <desc> | delete <num> — snapper snapshots
function cave-btrfs-snapshot
    if test (count $argv) -lt 1
        echo "Usage: cave-btrfs-snapshot list | create <desc> | delete <num>" >&2
        return 1
    end
    switch $argv[1]
        case list
            fmt_heading "Snapper Snapshots (root + home)"
            echo ""
            echo "── config: root ──"
            __btrfs_run snapper -c root list; or return 1
            echo ""
            echo "── config: home ──"
            __btrfs_run snapper -c home list; or return 1
        case create
            if test (count $argv) -ne 2
                echo "Usage: cave-btrfs-snapshot create <description>" >&2
                return 1
            end
            __btrfs_confirm "Create @home snapshot '$argv[2]'"; or return 1
            __btrfs_exec_or_print sudo -n snapper -c home create --description "$argv[2]"
        case delete
            if test (count $argv) -ne 2
                echo "Usage: cave-btrfs-snapshot delete <snapshot-number>" >&2
                return 1
            end
            if not string match -qr '^[0-9]+$' -- "$argv[2]"
                echo "Snapshot number must be numeric: $argv[2]" >&2
                return 1
            end
            __btrfs_confirm "Delete @home snapshot #$argv[2]"; or return 1
            __btrfs_exec_or_print sudo -n snapper -c home delete "$argv[2]"
        case '*'
            echo "Unknown action: $argv[1] (use list, create, or delete)" >&2
            return 1
    end
end

# cave-btrfs-subvol create <path> — create a subvolume
function cave-btrfs-subvol
    if test (count $argv) -ne 2; or test "$argv[1]" != "create"
        echo "Usage: cave-btrfs-subvol create <path>" >&2
        return 1
    end
    if string match -q '/boot*' -- "$argv[2]"
        echo "Refusing to touch /boot: $argv[2]" >&2
        return 1
    end
    if not string match -q '/*' -- "$argv[2]"
        echo "Path must be absolute: $argv[2]" >&2
        return 1
    end
    __btrfs_confirm "Create subvolume '$argv[2]'"; or return 1
    __btrfs_exec_or_print sudo -n btrfs subvolume create "$argv[2]"
end

# cave-btrfs-scrub start [--yes] — start a scrub (destructive-confirm)
function cave-btrfs-scrub
    if test (count $argv) -eq 0
        echo "Usage: cave-btrfs-scrub start [--yes]" >&2
        return 1
    end
    if test "$argv[1]" != "start"
        echo "Unknown action: $argv[1] (use start)" >&2
        return 1
    end
    set -l assume_yes false
    for a in $argv[2..-1]
        switch $a
            case --yes
                set assume_yes true
            case '*'
                echo "Unknown option: $a (usage: cave-btrfs-scrub start [--yes])" >&2
                return 1
        end
    end
    if test "$assume_yes" = false
        __btrfs_confirm "Start btrfs scrub on / (hours of IO)"; or return 1
    end
    __btrfs_exec_or_print sudo -n btrfs scrub start /
end

# cave-btrfs-balance start [--yes] — start a filtered balance (destructive-confirm)
function cave-btrfs-balance
    if test (count $argv) -eq 0
        echo "Usage: cave-btrfs-balance start [--yes]" >&2
        return 1
    end
    if test "$argv[1]" != "start"
        echo "Unknown action: $argv[1] (use start)" >&2
        return 1
    end
    set -l assume_yes false
    for a in $argv[2..-1]
        switch $a
            case --yes
                set assume_yes true
            case '*'
                echo "Unknown option: $a (usage: cave-btrfs-balance start [--yes])" >&2
                return 1
        end
    end
    if test "$assume_yes" = false
        __btrfs_confirm "Start btrfs balance (dusage=50/musage=50) on /"; or return 1
    end
    __btrfs_exec_or_print sudo -n btrfs balance start -dusage=50 -musage=50 /
end

# cave-btrfs-snapper list | status | diff <config> <num> — snapper surfaces
function cave-btrfs-snapper
    if test (count $argv) -lt 1
        echo "Usage: cave-btrfs-snapper list | status | diff <root|home> <num>" >&2
        return 1
    end
    switch $argv[1]
        case list
            cave-btrfs-snapshot list
        case status
            fmt_heading "Snapper Status"
            echo ""
            if systemctl is-active snapper-timeline.timer >/dev/null 2>&1
                fmt_kv "timeline.timer" "active"
            else
                fmt_kv "timeline.timer" "inactive"
            end
            for cfg in root home
                set -l last
                if not set last (__btrfs_run snapper -c $cfg list 2>/dev/null | tail -1)
                    set last "(unavailable)"
                end
                fmt_kv $cfg $last
            end
        case diff
            if test (count $argv) -ne 3
                echo "Usage: cave-btrfs-snapper diff <root|home> <snapshot-number>" >&2
                return 1
            end
            switch $argv[2]
                case root home
                case '*'
                    echo "Unknown config: $argv[2] (use root or home)" >&2
                    return 1
            end
            if not string match -qr '^[0-9]+$' -- "$argv[3]"
                echo "Snapshot number must be numeric: $argv[3]" >&2
                return 1
            end
            __btrfs_run snapper -c "$argv[2]" diff "$argv[3]" 0
        case '*'
            echo "Unknown action: $argv[1] (use list, status, or diff)" >&2
            return 1
    end
end
