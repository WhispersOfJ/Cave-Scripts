# ============================================================================
# cave-nzbdav — NzbDAV queue/history/stats + mount health
# ============================================================================
# desc: nzbdav queue, history, stats, dedup-check, delete-failures, mount-health
# ============================================================================

# cave-nzbdav-queue — Show NzbDAV current Usenet download queue
function cave-nzbdav-queue --description 'NzbDAV current Usenet download queue'
    __nzbdav_api GET queue
end

# cave-nzbdav-history — NzbDAV download history
function cave-nzbdav-history --description 'NzbDAV download history'
    __nzbdav_api GET history
end

# cave-nzbdav-stats — NzbDAV stats
function cave-nzbdav-stats --description 'NzbDAV stats'
    __nzbdav_api GET stats
end

# cave-nzbdav-dedup-check — canonical implementation lives in cave-disk

# cave-nzbdav-delete-failures — canonical implementation lives in cave-disk

# cave-mount-health — Check FUSE mount health
function cave-mount-health --description 'Check FUSE mount health'
    fmt_heading "Mount Health"
    echo ""
    set -l mount "/mnt/remote/nzbdav"

    if test -d "$mount"
        echo "  $mount  "(fmt_status_dot "present")
    else
        echo "  $mount  "(fmt_status_dot "missing")
    end

    # Authoritative check: the rclone sidecar's own healthcheck
    if type -q docker
        if docker exec nzbdav_rclone mountpoint -q /mnt/remote/nzbdav 2>/dev/null
            echo "  rclone mount  "(fmt_status_dot "healthy")
        else
            echo "  rclone mount  "(fmt_status_dot "dead")
        end
    end

    # Content flows through the WebDAV root served by nzbdav
    set -l entries (timeout 10 ls "$mount" 2>/dev/null | wc -l | string trim)
    if test "$entries" -gt 0 2>/dev/null
        echo "  content  "(fmt_status_dot "listing ok")"  ($entries entries)"
    else
        echo "  content  "(fmt_status_dot "empty/unreachable")
    end
end
