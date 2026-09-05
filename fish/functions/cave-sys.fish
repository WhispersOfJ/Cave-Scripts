# ============================================================================
# cave-sys — host diagnostics & maintenance (no API dependency)
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
function cave-sys-aur-audit --description 'AUR security audit'
    if type -q arch-audit
        arch-audit
    else
        echo "arch-audit not installed. Listing foreign packages:"
        pacman -Qmq
    end
end

# cave-sys-claude-home — cd to ~/Claude and launch Claude Code
function cave-sys-claude-home --description 'cd to ~/Claude and launch Claude Code'
    cd ~/Claude; or return 1
    claude --dangerously-skip-permissions .
end

# cave-sys-cron-list — system timers, user timers, and crontab
function cave-sys-cron-list --description 'system timers, user timers, and crontab'
    echo "=== System Timers ==="
    systemctl list-timers --all --no-pager 2>/dev/null | head -20
    echo ""
    echo "=== User Timers ==="
    systemctl --user list-timers --all --no-pager 2>/dev/null | head -20
    echo ""
    echo "=== Crontab ==="
    crontab -l 2>/dev/null; or echo "(no crontab)"
end

# cave-sys-disk-free [warn-pct] [crit-pct] — disk free with thresholds
function cave-sys-disk-free --description 'disk free with pass/warn/fail thresholds'
    set -l warn 80
    set -l crit 90
    test (count $argv) -ge 1; and set warn "$argv[1]"
    test (count $argv) -ge 2; and set crit "$argv[2]"
    df -h -x tmpfs -x devtmpfs -x overlay -x squashfs \
        --output=target,size,used,avail,pcent 2>/dev/null | tail -n +2 | \
    while read -l target size used avail pcent
        set -l pct (string replace -r '%$' '' -- "$pcent")
        set -l mark ok
        if test "$pct" -ge "$crit"
            set mark FAIL
        else if test "$pct" -ge "$warn"
            set mark WARN
        end
        printf "[%s] %-20s %6s used / %6s avail (%s%%)\n" "$mark" "$target" "$used" "$avail" "$pct"
    end
end

# cave-sys-disk-health — SMART health summary for every physical disk
function cave-sys-disk-health --description 'SMART health summary for every physical disk'
    if not type -q smartctl
        echo "smartctl not found — install smartmontools." >&2
        return 1
    end
    for disk in /dev/sd? /dev/nvme?n?
        test -b "$disk"; or continue
        echo "=== $disk ==="
        sudo smartctl -H "$disk" 2>/dev/null | grep -E "SMART overall|Device Model|SMART Health"
    end
end

# cave-sys-firewall-status — active nftables rules + listening ports
function cave-sys-firewall-status --description 'active nftables rules + listening ports'
    echo "=== Listening Ports ==="
    ss -tlnp 2>/dev/null | head -30
    echo ""
    echo "=== nftables ==="
    sudo nft list ruleset 2>/dev/null | head -30; or echo "nft not available"
end

# cave-sys-flatpak-updates [--apply] — list or apply pending Flatpak updates
function cave-sys-flatpak-updates --description 'list (or --apply) pending Flatpak updates'
# complete: --apply
    if not type -q flatpak
        echo "Flatpak not installed."
        return 1
    end
    if contains -- --apply $argv
        flatpak update -y
    else
        flatpak update
    end
end

# cave-sys-git-status-all — git status across every repo under ~/Claude
function cave-sys-git-status-all --description 'git status across every repo under ~/Claude'
    for dir in ~/Claude/*/
        if test -d "$dir/.git"
            set -l name (basename "$dir")
            set -l status (git -C "$dir" status --short 2>/dev/null)
            if test -n "$status"
                echo "=== $name ==="
                echo "$status"
                echo ""
            end
        end
    end
end

# cave-sys-journal-errors — error-or-worse journal entries since last boot
function cave-sys-journal-errors --description 'error-or-worse journal entries since last boot'
    journalctl -p err -b --no-pager -o short-iso 2>/dev/null | tail -50
end

# cave-sys-journal-size [--vacuum-size SIZE] — journald usage; optionally vacuum
function cave-sys-journal-size --description 'journald usage; optionally vacuum with --vacuum-size SIZE'
# complete: --vacuum-size
    if contains -- --vacuum-size $argv
        set -l idx (contains -i -- --vacuum-size $argv)
        # fish: contains -i gives 1-based index; next arg is the size
        sudo journalctl --vacuum-size="$argv[(math $idx + 1)]"
    else
        journalctl --disk-usage
    end
end

# cave-sys-kernel-check — compare running vs installed kernel
function cave-sys-kernel-check --description 'compare running vs installed kernel'
    set -l running (uname -r)
    set -l installed (pacman -Q linux 2>/dev/null | awk '{print $2}')
    echo "Running:  $running"
    echo "Installed: $installed"
    if test "$running" != "$installed"
        echo "MISMATCH — a reboot is needed."
        return 1
    else
        echo "OK — running kernel matches installed."
    end
end

# cave-sys-mem-pressure — kernel PSI for memory, CPU, and IO
function cave-sys-mem-pressure --description 'kernel PSI for memory, CPU, and IO'
    if test -f /proc/pressure/memory
        echo "=== Memory ==="
        cat /proc/pressure/memory
    else
        echo "PSI not available (kernel < 4.20 or not enabled)"
    end
    if test -f /proc/pressure/cpu
        echo ""
        echo "=== CPU ==="
        cat /proc/pressure/cpu
    end
    if test -f /proc/pressure/io
        echo ""
        echo "=== IO ==="
        cat /proc/pressure/io
    end
end

# cave-sys-pkg-clean-cache [keep-N] — vacuum pacman cache to last N versions
function cave-sys-pkg-clean-cache --description 'vacuum pacman cache to last N versions'
# complete: 1|2|3|5|10
    set -l keep 2
    test (count $argv) -ge 1; and set keep "$argv[1]"
    sudo paccache -rk "$keep"
end

# cave-sys-pkg-history [N] — tail of pacman transaction log
function cave-sys-pkg-history --description 'tail of pacman transaction log'
    set -l count 20
    test (count $argv) -ge 1; and set count "$argv[1]"
    tail -n "$count" /var/log/pacman.log 2>/dev/null
end

# cave-sys-pkg-orphans [--remove] — list or remove orphaned packages
function cave-sys-pkg-orphans --description 'list (or --remove) orphaned packages'
# complete: --remove
    set -l orphans (pacman -Qdtq 2>/dev/null)
    if test (count $orphans) -eq 0
        echo "No orphaned packages."
        return 0
    end
    if contains -- --remove $argv
        echo "Removing orphans..."
        sudo pacman -Rns $orphans
    else
        echo "$orphans"
    end
end

# cave-sys-pkg-update [--yes] — run pacman/AUR system update
function cave-sys-pkg-update --description 'run pacman/AUR system update (prompts unless -y)'
# complete: -y|--yes
    if not type -q pacman
        echo "Not an Arch-based host." >&2
        return 1
    end
    if not contains -- --yes $argv; and not contains -- -y $argv
        printf 'Run a full system update now? [y/N] '
        set -l confirm
        read -l confirm
        if not string match -qr '^[Yy]' -- "$confirm"
            echo "Aborted."
            return 1
        end
    end
    sudo -n pacman -Syu --noconfirm
    set -l status_pacman $status
    if type -q paru
        paru -Sua --noconfirm
    else if type -q yay
        yay -Sua --noconfirm
    end
    return "$status_pacman"
end

# cave-sys-pkg-updates — pending pacman + AUR updates
function cave-sys-pkg-updates --description 'pending pacman + AUR updates'
    if not type -q pacman
        echo "Not an Arch-based host." >&2
        return 1
    end
    echo "=== Pacman ==="
    pacman -Qu 2>/dev/null | head -20
    echo ""
    if type -q paru
        echo "=== AUR (paru) ==="
        paru -Qua 2>/dev/null | head -20
    else if type -q yay
        echo "=== AUR (yay) ==="
        yay -Qua 2>/dev/null | head -20
    end
end

# cave-sys-reboot-check — check for pending reboot marker
function cave-sys-reboot-check --description 'check for pending reboot marker'
    if test -f /run/reboot-required
        echo "Reboot required (/run/reboot-required exists)"
        return 1
    else
        echo "No reboot pending."
    end
    cave-sys-kernel-check
end

# cave-sys-service-failed — failed systemd units
function cave-sys-service-failed --description 'failed systemd units'
    echo "=== System ==="
    systemctl --failed --no-pager 2>/dev/null
    echo ""
    echo "=== User ==="
    systemctl --user --failed --no-pager 2>/dev/null
end

# cave-sys-ssh-doctor — check SSH config health
function cave-sys-ssh-doctor --description 'check SSH config health'
    echo "=== ~/.ssh directory ==="
    if test -d ~/.ssh
        echo "OK"
    else
        echo "MISSING — ~/.ssh does not exist"
    end
    echo ""
    echo "=== GitHub in known_hosts ==="
    if grep -q github.com ~/.ssh/known_hosts 2>/dev/null
        echo "OK"
    else
        echo "MISSING — add with: ssh-keyscan github.com >> ~/.ssh/known_hosts"
    end
    echo ""
    echo "=== Private key ==="
    if test -f ~/.ssh/id_ed25519
        echo "OK (~/.ssh/id_ed25519)"
    else if test -f ~/.ssh/id_rsa
        echo "OK (~/.ssh/id_rsa)"
    else
        echo "MISSING — no private key found"
    end
end

# cave-sys-timer-status — stack timer states and last runs
function cave-sys-timer-status --description 'stack timer states and last runs'
    systemctl list-timers --all --no-pager 2>/dev/null | grep -i stack
end

# cave-sys-uptime-report — uptime, load average, last shutdown
function cave-sys-uptime-report --description 'uptime, load average, last shutdown'
    echo "=== Uptime ==="
    uptime
    echo ""
    echo "=== Last shutdown ==="
    last -x | head -5
end

# cave-sys-zombie-check — list zombie/defunct processes
function cave-sys-zombie-check --description 'list zombie/defunct processes'
    set -l zombies (ps aux | awk '$8 ~ /Z/ {print}')
    if test (count $zombies) -eq 0
        echo "No zombie processes."
    else
        echo "$zombies"
    end
end
