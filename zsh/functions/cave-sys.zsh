# ============================================================================
# cave-sys — host diagnostics & maintenance (no API dependency) (zsh port)
# ============================================================================
# desc: host diagnostics & maintenance (no API dependency)
# Ported from services/host-tools/functions/stack-*.fish (M1 ledger section C)
# and renamed stack-* → cave-sys-* per decision L2. These run directly on the
# host; they never touch the media stack. Safety classes from the registry:
#   read-only           most commands (safe to run live)
#   mutating-safe       cave-sys-pkg-update, cave-sys-flatpak-updates (--apply),
#                       cave-sys-pkg-orphans (--remove), cave-sys-pkg-clean-cache
# ============================================================================

# cave-sys-aur-audit — AUR security audit
cave-sys-aur-audit() {
    if command -v arch-audit >/dev/null 2>&1; then
        arch-audit
    else
        echo "arch-audit not installed. Listing foreign packages:"
        pacman -Qmq
    fi
}

# cave-sys-claude-home — cd to ~/Claude and launch Claude Code
cave-sys-claude-home() {
    cd ~/Claude || return 1
    claude --dangerously-skip-permissions .
}

# cave-sys-cron-list — system timers, user timers, and crontab
cave-sys-cron-list() {
    echo "=== System Timers ==="
    systemctl list-timers --all --no-pager 2>/dev/null | head -20
    echo ""
    echo "=== User Timers ==="
    systemctl --user list-timers --all --no-pager 2>/dev/null | head -20
    echo ""
    echo "=== Crontab ==="
    crontab -l 2>/dev/null || echo "(no crontab)"
}

# cave-sys-disk-free [warn-pct] [crit-pct] — disk free with thresholds
cave-sys-disk-free() {
    local warn=80 crit=90
    [ "$#" -ge 1 ] && warn="$1"
    [ "$#" -ge 2 ] && crit="$2"
    df -h -x tmpfs -x devtmpfs -x overlay -x squashfs \
        --output=target,size,used,avail,pcent 2>/dev/null | tail -n +2 | \
    while read -r target size used avail pcent; do
        local pct="${pcent%\%}" mark=ok
        if [ "$pct" -ge "$crit" ]; then
            mark=FAIL
        elif [ "$pct" -ge "$warn" ]; then
            mark=WARN
        fi
        printf "[%s] %-20s %6s used / %6s avail (%s%%)\n" "$mark" "$target" "$used" "$avail" "$pct"
    done
}

# cave-sys-disk-health — SMART health summary for every physical disk
cave-sys-disk-health() {
    if ! command -v smartctl >/dev/null 2>&1; then
        echo "smartctl not found — install smartmontools." >&2
        return 1
    fi
    local disk
    for disk in /dev/sd? /dev/nvme?n?; do
        [ -b "$disk" ] || continue
        echo "=== $disk ==="
        sudo smartctl -H "$disk" 2>/dev/null | grep -E "SMART overall|Device Model|SMART Health"
    done
}

# cave-sys-firewall-status — active nftables rules + listening ports
cave-sys-firewall-status() {
    echo "=== Listening Ports ==="
    ss -tlnp 2>/dev/null | head -30
    echo ""
    echo "=== nftables ==="
    sudo nft list ruleset 2>/dev/null | head -30 || echo "nft not available"
}

# cave-sys-flatpak-updates [--apply] — list or apply pending Flatpak updates
cave-sys-flatpak-updates() {
# complete: --apply
    if ! command -v flatpak >/dev/null 2>&1; then
        echo "Flatpak not installed."
        return 1
    fi
    if [[ " $* " == *" --apply "* ]]; then
        flatpak update -y
    else
        flatpak update
    fi
}

# cave-sys-git-status-all — git status across every repo under ~/Claude
cave-sys-git-status-all() {
    local dir name status
    for dir in ~/Claude/*/; do
        if [ -d "$dir/.git" ]; then
            name="$(basename "$dir")"
            status="$(git -C "$dir" status --short 2>/dev/null)"
            if [ -n "$status" ]; then
                echo "=== $name ==="
                echo "$status"
                echo ""
            fi
        fi
    done
}

# cave-sys-journal-errors — error-or-worse journal entries since last boot
cave-sys-journal-errors() {
    journalctl -p err -b --no-pager -o short-iso 2>/dev/null | tail -50
}

# cave-sys-journal-size [--vacuum-size SIZE] — journald usage; optionally vacuum
cave-sys-journal-size() {
# complete: --vacuum-size
    local idx
    if [[ " $* " == *" --vacuum-size "* ]]; then
        idx="$(echo "$*" | tr ' ' '\n' | grep -nx -- --vacuum-size | head -1 | cut -d: -f1)"
        # fish: contains -i gave 1-based index; next arg is the size
        sudo journalctl --vacuum-size="$(echo "$*" | tr ' ' '\n' | sed -n "$((idx + 1))p")"
    else
        journalctl --disk-usage
    fi
}

# cave-sys-kernel-check — compare running vs installed kernel
cave-sys-kernel-check() {
    local running installed
    running="$(uname -r)"
    installed="$(pacman -Q linux 2>/dev/null | awk '{print $2}')"
    echo "Running:  $running"
    echo "Installed: $installed"
    if [ "$running" != "$installed" ]; then
        echo "MISMATCH — a reboot is needed."
        return 1
    else
        echo "OK — running kernel matches installed."
    fi
}

# cave-sys-mem-pressure — kernel PSI for memory, CPU, and IO
cave-sys-mem-pressure() {
    if [ -f /proc/pressure/memory ]; then
        echo "=== Memory ==="
        cat /proc/pressure/memory
    else
        echo "PSI not available (kernel < 4.20 or not enabled)"
    fi
    if [ -f /proc/pressure/cpu ]; then
        echo ""
        echo "=== CPU ==="
        cat /proc/pressure/cpu
    fi
    if [ -f /proc/pressure/io ]; then
        echo ""
        echo "=== IO ==="
        cat /proc/pressure/io
    fi
}

# cave-sys-pkg-clean-cache [keep-N] — vacuum pacman cache to last N versions
cave-sys-pkg-clean-cache() {
# complete: 1|2|3|5|10
    local keep=2
    [ "$#" -ge 1 ] && keep="$1"
    sudo paccache -rk "$keep"
}

# cave-sys-pkg-history [N] — tail of pacman transaction log
cave-sys-pkg-history() {
    local count=20
    [ "$#" -ge 1 ] && count="$1"
    tail -n "$count" /var/log/pacman.log 2>/dev/null
}

# cave-sys-pkg-orphans [--remove] — list or remove orphaned packages
cave-sys-pkg-orphans() {
# complete: --remove
    local orphans
    orphans="$(pacman -Qdtq 2>/dev/null)"
    if [ -z "$orphans" ]; then
        echo "No orphaned packages."
        return 0
    fi
    if [[ " $* " == *" --remove "* ]]; then
        echo "Removing orphans..."
        sudo pacman -Rns $orphans
    else
        echo "$orphans"
    fi
}

# cave-sys-pkg-update [--yes] — run pacman/AUR system update
cave-sys-pkg-update() {
# complete: -y|--yes
    if ! command -v pacman >/dev/null 2>&1; then
        echo "Not an Arch-based host." >&2
        return 1
    fi
    if [[ " $* " != *" --yes "* ]] && [[ " $* " != *" -y "* ]]; then
        local confirm
        read -r -p "Run a full system update now? [y/N] " confirm
        if ! printf '%s' "$confirm" | grep -qE '^[Yy]'; then
            echo "Aborted."
            return 1
        fi
    fi
    sudo -n pacman -Syu --noconfirm
    local status_pacman=$?
    if command -v paru >/dev/null 2>&1; then
        paru -Sua --noconfirm
    elif command -v yay >/dev/null 2>&1; then
        yay -Sua --noconfirm
    fi
    return "$status_pacman"
}

# cave-sys-pkg-updates — pending pacman + AUR updates
cave-sys-pkg-updates() {
    if ! command -v pacman >/dev/null 2>&1; then
        echo "Not an Arch-based host." >&2
        return 1
    fi
    echo "=== Pacman ==="
    pacman -Qu 2>/dev/null | head -20
    echo ""
    if command -v paru >/dev/null 2>&1; then
        echo "=== AUR (paru) ==="
        paru -Qua 2>/dev/null | head -20
    elif command -v yay >/dev/null 2>&1; then
        echo "=== AUR (yay) ==="
        yay -Qua 2>/dev/null | head -20
    fi
}

# cave-sys-reboot-check — check for pending reboot marker
cave-sys-reboot-check() {
    if [ -f /run/reboot-required ]; then
        echo "Reboot required (/run/reboot-required exists)"
        return 1
    else
        echo "No reboot pending."
    fi
    cave-sys-kernel-check
}

# cave-sys-service-failed — failed systemd units
cave-sys-service-failed() {
    echo "=== System ==="
    systemctl --failed --no-pager 2>/dev/null
    echo ""
    echo "=== User ==="
    systemctl --user --failed --no-pager 2>/dev/null
}

# cave-sys-ssh-doctor — check SSH config health
cave-sys-ssh-doctor() {
    echo "=== ~/.ssh directory ==="
    if [ -d ~/.ssh ]; then
        echo "OK"
    else
        echo "MISSING — ~/.ssh does not exist"
    fi
    echo ""
    echo "=== GitHub in known_hosts ==="
    if grep -q github.com ~/.ssh/known_hosts 2>/dev/null; then
        echo "OK"
    else
        echo "MISSING — add with: ssh-keyscan github.com >> ~/.ssh/known_hosts"
    fi
    echo ""
    echo "=== Private key ==="
    if [ -f ~/.ssh/id_ed25519 ]; then
        echo "OK (~/.ssh/id_ed25519)"
    elif [ -f ~/.ssh/id_rsa ]; then
        echo "OK (~/.ssh/id_rsa)"
    else
        echo "MISSING — no private key found"
    fi
}

# cave-sys-timer-status — stack timer states and last runs
cave-sys-timer-status() {
    systemctl list-timers --all --no-pager 2>/dev/null | grep -i stack
}

# cave-sys-uptime-report — uptime, load average, last shutdown
cave-sys-uptime-report() {
    echo "=== Uptime ==="
    uptime
    echo ""
    echo "=== Last shutdown ==="
    last -x | head -5
}

# cave-sys-zombie-check — list zombie/defunct processes
cave-sys-zombie-check() {
    local zombies
    zombies="$(ps aux | awk '$8 ~ /Z/ {print}')"
    if [ -z "$zombies" ]; then
        echo "No zombie processes."
    else
        echo "$zombies"
    fi
}