# ============================================================================
# cave-btrfs.sh — btrfs filesystem info & maintenance (M3, spec §6.4/§7)
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

__btrfs_run() {
    if sudo -n true >/dev/null 2>&1; then
        sudo -n "$@"
    else
        echo "cave-btrfs: '$*' needs root (passwordless sudo unavailable)" >&2
        return 1
    fi
}

__btrfs_exec_or_print() {
    echo "+ $*"
    if [ "${CAVE_BTRFS_DRYRUN:-0}" = "1" ]; then
        return 0
    fi
    "$@"
}

__btrfs_confirm() { # $1 = action label
    if [ "${CAVE_BTRFS_DRYRUN:-0}" = "1" ]; then
        return 0
    fi
    printf '%s? [y/N] ' "$1"
    local reply
    read -r reply
    case "$reply" in
        y|Y) return 0 ;;
        *) echo "Aborted."; return 1 ;;
    esac
}

# cave-btrfs-usage — filesystem usage by class (unprivileged)
cave-btrfs-usage() {
    fmt_heading "Btrfs Usage"
    echo ""
    if ! btrfs filesystem df / 2>/dev/null; then
        echo "btrfs filesystem df unavailable — falling back to df:"
        df -h /
    fi
}

# cave-btrfs-subvolumes — subvolume layout of the fs root
cave-btrfs-subvolumes() {
    fmt_heading "Btrfs Subvolumes"
    echo ""
    if sudo -n true >/dev/null 2>&1; then
        sudo -n btrfs subvolume list / 2>/dev/null || echo "subvolume list failed"
    else
        echo "(passwordless sudo unavailable — showing mount-level layout)"
        findmnt -t btrfs -o TARGET,SOURCE,OPTIONS
    fi
}

# cave-btrfs-device-stats — per-device error counters
cave-btrfs-device-stats() {
    fmt_heading "Btrfs Device Stats"
    echo ""
    __btrfs_run btrfs device stats /
}

# cave-btrfs-scrub-status — scrub state (idle or running)
cave-btrfs-scrub-status() {
    fmt_heading "Btrfs Scrub Status"
    echo ""
    __btrfs_run btrfs scrub status /
}

# cave-btrfs-balance-status — balance state (none or in progress)
cave-btrfs-balance-status() {
    fmt_heading "Btrfs Balance Status"
    echo ""
    __btrfs_run btrfs balance status /
}

# cave-btrfs-qgroup — quota groups (graceful when quotas are disabled)
cave-btrfs-qgroup() {
    fmt_heading "Btrfs Qgroups"
    echo ""
    if ! __btrfs_run btrfs qgroup show / 2>/dev/null; then
        echo "quota group support is disabled on this filesystem"
        return 0
    fi
}

# cave-btrfs-snapshot list | create <desc> | delete <num> — snapper snapshots
cave-btrfs-snapshot() {
# complete: list|create|delete
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-btrfs-snapshot list | create <desc> | delete <num>" >&2
        return 1
    fi
    case "$1" in
        list)
            fmt_heading "Snapper Snapshots (root + home)"
            echo ""
            echo "── config: root ──"
            __btrfs_run snapper -c root list || return 1
            echo ""
            echo "── config: home ──"
            __btrfs_run snapper -c home list || return 1
            ;;
        create)
            if [ "$#" -ne 2 ]; then
                echo "Usage: cave-btrfs-snapshot create <description>" >&2
                return 1
            fi
            __btrfs_confirm "Create @home snapshot '$2'" || return 1
            __btrfs_exec_or_print sudo -n snapper -c home create --description "$2"
            ;;
        delete)
            if [ "$#" -ne 2 ]; then
                echo "Usage: cave-btrfs-snapshot delete <snapshot-number>" >&2
                return 1
            fi
            case "$2" in
                ''|*[!0-9]*) echo "Snapshot number must be numeric: $2" >&2; return 1 ;;
            esac
            __btrfs_confirm "Delete @home snapshot #$2" || return 1
            __btrfs_exec_or_print sudo -n snapper -c home delete "$2"
            ;;
        *)
            echo "Unknown action: $1 (use list, create, or delete)" >&2
            return 1
            ;;
    esac
}

# cave-btrfs-subvol create <path> — create a subvolume
cave-btrfs-subvol() {
# complete: create
    if [ "$#" -ne 2 ] || [ "$1" != "create" ]; then
        echo "Usage: cave-btrfs-subvol create <path>" >&2
        return 1
    fi
    case "$2" in
        /boot*) echo "Refusing to touch /boot: $2" >&2; return 1 ;;
        /*) ;;
        *) echo "Path must be absolute: $2" >&2; return 1 ;;
    esac
    __btrfs_confirm "Create subvolume '$2'" || return 1
    __btrfs_exec_or_print sudo -n btrfs subvolume create "$2"
}

# cave-btrfs-scrub start [--yes] — start a scrub (destructive-confirm)
cave-btrfs-scrub() {
# complete: start
# danger: true
    if [ "$#" -eq 0 ]; then
        echo "Usage: cave-btrfs-scrub start [--yes]" >&2
        return 1
    fi
    if [ "$1" != "start" ]; then
        echo "Unknown action: $1 (use start)" >&2
        return 1
    fi
    local assume_yes=false a
    shift
    for a in "$@"; do
        case "$a" in
            --yes) assume_yes=true ;;
            *) echo "Unknown option: $a (usage: cave-btrfs-scrub start [--yes])" >&2; return 1 ;;
        esac
    done
    if ! $assume_yes; then
        __btrfs_confirm "Start btrfs scrub on / (hours of IO)" || return 1
    fi
    __btrfs_exec_or_print sudo -n btrfs scrub start /
}

# cave-btrfs-balance start [--yes] — start a filtered balance (destructive-confirm)
cave-btrfs-balance() {
# complete: start
# danger: true
    if [ "$#" -eq 0 ]; then
        echo "Usage: cave-btrfs-balance start [--yes]" >&2
        return 1
    fi
    if [ "$1" != "start" ]; then
        echo "Unknown action: $1 (use start)" >&2
        return 1
    fi
    local assume_yes=false a
    shift
    for a in "$@"; do
        case "$a" in
            --yes) assume_yes=true ;;
            *) echo "Unknown option: $a (usage: cave-btrfs-balance start [--yes])" >&2; return 1 ;;
        esac
    done
    if ! $assume_yes; then
        __btrfs_confirm "Start btrfs balance (dusage=50/musage=50) on /" || return 1
    fi
    __btrfs_exec_or_print sudo -n btrfs balance start -dusage=50 -musage=50 /
}

# cave-btrfs-snapper list | status | diff <config> <num> — snapper surfaces
cave-btrfs-snapper() {
# complete: list|status|diff
    if [ "$#" -lt 1 ]; then
        echo "Usage: cave-btrfs-snapper list | status | diff <root|home> <num>" >&2
        return 1
    fi
    case "$1" in
        list)
            cave-btrfs-snapshot list
            ;;
        status)
            fmt_heading "Snapper Status"
            echo ""
            if systemctl is-active snapper-timeline.timer >/dev/null 2>&1; then
                fmt_kv "timeline.timer" "active"
            else
                fmt_kv "timeline.timer" "inactive"
            fi
            for cfg in root home; do
                local last
                last="$(__btrfs_run snapper -c "$cfg" list 2>/dev/null | tail -1)" || last="(unavailable)"
                fmt_kv "$cfg" "$last"
            done
            ;;
        diff)
            if [ "$#" -ne 3 ]; then
                echo "Usage: cave-btrfs-snapper diff <root|home> <snapshot-number>" >&2
                return 1
            fi
            case "$2" in
                root|home) ;;
                *) echo "Unknown config: $2 (use root or home)" >&2; return 1 ;;
            esac
            case "$3" in
                ''|*[!0-9]*) echo "Snapshot number must be numeric: $3" >&2; return 1 ;;
            esac
            __btrfs_run snapper -c "$2" diff "$3" 0
            ;;
        *)
            echo "Unknown action: $1 (use list, status, or diff)" >&2
            return 1
            ;;
    esac
}
