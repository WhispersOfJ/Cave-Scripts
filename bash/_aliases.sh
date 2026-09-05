# ============================================================================
# _aliases.sh — permanent stack-* → cave-* alias layer (D21)
# ============================================================================
# Every stack-* command name forwards to its cave-* function so muscle
# memory, cron lines, and docs keep working indefinitely. Generated from
# spec/functions.yaml — regenerate with scripts/gen-aliases.sh (M2).
# Aliases are real functions (not bash aliases) so they work in scripts,
# completion, and non-interactive shells, and can be tested offline.
#
# Conformance: tests/bash/test_cave_scripts.sh asserts that every row in
# functions.yaml has a cave-* function AND a stack-* forwarder here, and
# that no stack-* forwarder lacks a cave-* target.
# ============================================================================

stack-activity-feed() { cave-activity-feed "$@"; }
stack-arr() { cave-arr "$@"; }
stack-arr-backlog() { cave-arr-backlog "$@"; }
stack-arr-blocklist() { cave-arr-blocklist "$@"; }
stack-arr-clear-blocklist() { cave-arr-clear-blocklist "$@"; }
stack-arr-import() { cave-arr-import "$@"; }
stack-arr-import-all() { cave-arr-import-all "$@"; }
stack-arr-import-candidates() { cave-arr-import-candidates "$@"; }
stack-arr-import-starvation() { cave-arr-import-starvation "$@"; }
stack-arr-logs() { cave-arr-logs "$@"; }
stack-arr-missing-aired() { cave-arr-missing-aired "$@"; }
stack-arr-queue-errors() { cave-arr-queue-errors "$@"; }
stack-arr-recently-added() { cave-arr-recently-added "$@"; }
stack-arr-toggle-search() { cave-arr-toggle-search "$@"; }
stack-arrival-notify() { cave-arrival-notify "$@"; }
stack-audit-residue() { cave-audit-residue "$@"; }
stack-aur-audit() { cave-sys-aur-audit "$@"; }
stack-backlog-status() { cave-backlog-status "$@"; }
stack-claude-full-backup() { cave-claude-full-backup "$@"; }
stack-claude-home() { cave-sys-claude-home "$@"; }
stack-command-queue-summary() { cave-command-queue-summary "$@"; }
stack-config-drift() { cave-config-drift "$@"; }
stack-container() { cave-container "$@"; }
stack-cron-list() { cave-sys-cron-list "$@"; }
stack-cutoff-unmet() { cave-cutoff-unmet "$@"; }
stack-disk-config-sizes() { cave-disk-config-sizes "$@"; }
stack-disk-free() { cave-sys-disk-free "$@"; }
stack-disk-health() { cave-sys-disk-health "$@"; }
stack-disk-reclaim() { cave-disk-reclaim "$@"; }
stack-docker-disk-usage() { cave-docker-disk-usage "$@"; }
stack-firewall-status() { cave-sys-firewall-status "$@"; }
stack-flatpak-updates() { cave-sys-flatpak-updates "$@"; }
stack-git-status-all() { cave-sys-git-status-all "$@"; }
stack-help() { cave-help "$@"; }
stack-image-check() { cave-image-check "$@"; }
stack-import-lists() { cave-import-lists "$@"; }
stack-journal-errors() { cave-sys-journal-errors "$@"; }
stack-journal-size() { cave-sys-journal-size "$@"; }
stack-kernel-check() { cave-sys-kernel-check "$@"; }
stack-letterboxd-history() { cave-letterboxd-history "$@"; }
stack-letterboxd-import() { cave-letterboxd-import "$@"; }
stack-letterboxd-track() { cave-letterboxd-track "$@"; }
stack-letterboxd-tracked() { cave-letterboxd-tracked "$@"; }
stack-letterboxd-untrack() { cave-letterboxd-untrack "$@"; }
stack-log-levels() { cave-log-levels "$@"; }
stack-loop-candidates() { cave-loop-candidates "$@"; }
stack-loop-exclude() { cave-loop-exclude "$@"; }
stack-loop-unmonitor() { cave-loop-unmonitor "$@"; }
stack-maintenance-digest() { cave-maintenance-digest "$@"; }
stack-mdblist-history() { cave-mdblist-history "$@"; }
stack-mdblist-import() { cave-mdblist-import "$@"; }
stack-mdblist-track() { cave-mdblist-track "$@"; }
stack-mdblist-tracked() { cave-mdblist-tracked "$@"; }
stack-mdblist-untrack() { cave-mdblist-untrack "$@"; }
stack-mem-pressure() { cave-sys-mem-pressure "$@"; }
stack-mount-health() { cave-mount-health "$@"; }
stack-notify-test() { cave-notify-test "$@"; }
stack-nzbdav-dedup-check() { cave-nzbdav-dedup-check "$@"; }
stack-nzbdav-delete-failures() { cave-nzbdav-delete-failures "$@"; }
stack-nzbdav-history() { cave-nzbdav-history "$@"; }
stack-nzbdav-queue() { cave-nzbdav-queue "$@"; }
stack-nzbdav-stats() { cave-nzbdav-stats "$@"; }
stack-oom-check() { cave-oom-check "$@"; }
stack-perms-check() { cave-perms-check "$@"; }
stack-pkg-clean-cache() { cave-sys-pkg-clean-cache "$@"; }
stack-pkg-history() { cave-sys-pkg-history "$@"; }
stack-pkg-orphans() { cave-sys-pkg-orphans "$@"; }
stack-pkg-update() { cave-sys-pkg-update "$@"; }
stack-pkg-updates() { cave-sys-pkg-updates "$@"; }
stack-plex() { cave-plex "$@"; }
stack-plex-analyze() { cave-plex-analyze "$@"; }
stack-plex-automatic-updates() { cave-plex-automatic-updates "$@"; }
stack-plex-backup-database() { cave-plex-backup-database "$@"; }
stack-plex-butler() { cave-plex-butler "$@"; }
stack-plex-butler-all() { cave-plex-butler-all "$@"; }
stack-plex-clean-cache-files() { cave-plex-clean-cache-files "$@"; }
stack-plex-clean-log-files() { cave-plex-clean-log-files "$@"; }
stack-plex-deep-media-analysis() { cave-plex-deep-media-analysis "$@"; }
stack-plex-duplicates() { cave-plex-duplicates "$@"; }
stack-plex-empty-trash() { cave-plex-empty-trash "$@"; }
stack-plex-garbage-collect-blobs() { cave-plex-garbage-collect-blobs "$@"; }
stack-plex-garbage-collect-media() { cave-plex-garbage-collect-media "$@"; }
stack-plex-generate-ad-markers() { cave-plex-generate-ad-markers "$@"; }
stack-plex-generate-chapter-thumbs() { cave-plex-generate-chapter-thumbs "$@"; }
stack-plex-generate-credits-markers() { cave-plex-generate-credits-markers "$@"; }
stack-plex-generate-intro-markers() { cave-plex-generate-intro-markers "$@"; }
stack-plex-generate-media-index() { cave-plex-generate-media-index "$@"; }
stack-plex-generate-voice-activity() { cave-plex-generate-voice-activity "$@"; }
stack-plex-image-clean() { cave-plex-image-clean "$@"; }
stack-plex-libraries() { cave-plex-libraries "$@"; }
stack-plex-loudness-analysis() { cave-plex-loudness-analysis "$@"; }
stack-plex-markers() { cave-plex-markers "$@"; }
stack-plex-music-analysis() { cave-plex-music-analysis "$@"; }
stack-plex-process-assets() { cave-plex-process-assets "$@"; }
stack-plex-recently-added() { cave-plex-recently-added "$@"; }
stack-plex-refresh-epg() { cave-plex-refresh-epg "$@"; }
stack-plex-refresh-libraries() { cave-plex-refresh-libraries "$@"; }
stack-plex-refresh-local-media() { cave-plex-refresh-local-media "$@"; }
stack-plex-sessions() { cave-plex-sessions "$@"; }
stack-plex-updates() { cave-plex-updates "$@"; }
stack-plex-upgrade-media-analysis() { cave-plex-upgrade-media-analysis "$@"; }
stack-prowlarr-indexers() { cave-prowlarr-indexers "$@"; }
stack-queue-autofix() { cave-queue-autofix "$@"; }
stack-queue-status() { cave-queue-status "$@"; }
stack-radarr-health() { cave-radarr-health "$@"; }
stack-radarr-prune() { cave-radarr-prune "$@"; }
stack-rating-imdb() { cave-rating-imdb "$@"; }
stack-rating-mdblist() { cave-rating-mdblist "$@"; }
stack-reboot-check() { cave-sys-reboot-check "$@"; }
stack-recent() { cave-recent "$@"; }
stack-requests() { cave-requests "$@"; }
stack-resource-check() { cave-resource-check "$@"; }
stack-restart-all() { cave-restart-all "$@"; }
stack-seerr-requests() { cave-seerr-requests "$@"; }
stack-service-failed() { cave-sys-service-failed "$@"; }
stack-sonarr-fix-episode-monitoring() { cave-sonarr-fix-episode-monitoring "$@"; }
stack-sonarr-prune() { cave-sonarr-prune "$@"; }
stack-ssh-doctor() { cave-sys-ssh-doctor "$@"; }
stack-status() { cave-status "$@"; }
stack-timer-status() { cave-sys-timer-status "$@"; }
stack-tmdb-missing() { cave-tmdb-missing "$@"; }
stack-top() { cave-top "$@"; }
stack-unwatched() { cave-unwatched "$@"; }
stack-uptime-report() { cave-sys-uptime-report "$@"; }
stack-version() { cave-version "$@"; }
stack-watchable() { cave-watchable "$@"; }
stack-worktree() { cave-worktree "$@"; }
stack-zombie-check() { cave-sys-zombie-check "$@"; }
