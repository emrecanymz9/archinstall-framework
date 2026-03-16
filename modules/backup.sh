#!/usr/bin/env bash
# modules/backup.sh - Backup and snapshot tools (snapper for btrfs, timeshift for ext4)
set -Eeuo pipefail

install_backup() {
    log_info "Installing backup/snapshot tools..."

    local filesystem
    filesystem=$(get_state "filesystem")

    if [[ "$filesystem" == "btrfs" ]]; then
        _install_snapper
    else
        _install_timeshift
    fi
}

_install_snapper() {
    log_info "Installing snapper (btrfs snapshots)..."

    run_cmd_interactive pacman -S --noconfirm --needed \
        snapper snap-pac \
        btrfs-assistant \
        grub-btrfs

    # Configure snapper for root subvolume
    # Unmount /.snapshots first (snapper will recreate it)
    umount /.snapshots 2>/dev/null || true
    rm -rf /.snapshots

    snapper -c root create-config /
    mount -a 2>/dev/null || true

    # Set reasonable snapshot limits
    local snapper_conf="/etc/snapper/configs/root"
    if [[ -f "$snapper_conf" ]]; then
        sed -i \
            -e 's/^TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE="1800"/' \
            -e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' \
            -e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' \
            -e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/' \
            -e 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' \
            -e 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' \
            "$snapper_conf"
    fi

    # Enable snapper timers
    run_cmd systemctl enable snapper-timeline.timer
    run_cmd systemctl enable snapper-cleanup.timer

    log_info "snapper configured for btrfs root."
}

_install_timeshift() {
    log_info "Installing Timeshift (ext4/rsync snapshots)..."

    # timeshift is in AUR; install rsync fallback from official repos
    run_cmd_interactive pacman -S --noconfirm --needed rsync

    # Try timeshift from AUR helper if available, otherwise skip
    if command -v yay &>/dev/null; then
        run_cmd_interactive yay -S --noconfirm timeshift
    elif command -v paru &>/dev/null; then
        run_cmd_interactive paru -S --noconfirm timeshift
    else
        log_warn "Timeshift is in AUR. Install manually after setting up an AUR helper:"
        log_warn "  yay -S timeshift  OR  paru -S timeshift"
    fi

    log_info "Backup tools installed."
}