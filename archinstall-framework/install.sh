#!/usr/bin/env bash

set -Eeuo pipefail

# ------------------------------------------------------------
# Globals
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/ui.sh"
source "$LIB_DIR/state.sh"

# Core modules (execution phase)
source "$LIB_DIR/disk.sh"
source "$LIB_DIR/luks.sh"
source "$LIB_DIR/filesystem.sh"
source "$LIB_DIR/kernel.sh"
source "$LIB_DIR/zram.sh"
source "$LIB_DIR/limine.sh"
source "$LIB_DIR/secureboot.sh"

# ------------------------------------------------------------
# State
# ------------------------------------------------------------

STATE_PHASE="configuration"

# ------------------------------------------------------------
# Screens
# ------------------------------------------------------------

screen_welcome() {
    ui_msg "Archinstall Framework (2026 Core Installer)

This installer will build a secure, encrypted Arch Linux base system.

Defaults:
- LUKS2
- Btrfs (zstd:5)
- ZRAM
- linux-zen
- Limine

Press Continue to proceed."
}

screen_boot_mode() {
    detect_boot_mode
    ui_msg "Detected boot mode: $BOOT_MODE"
}

screen_disk_selection() {
    select_disk
}

screen_disk_mode() {
    select_disk_mode
}

screen_review() {
    ui_review_summary
}

# ------------------------------------------------------------
# Execution
# ------------------------------------------------------------

execute_installation() {
    STATE_PHASE="execution"

    ui_log "Starting execution phase..."

    plan_disk_layout
    apply_disk_layout

    setup_luks
    setup_btrfs

    mount_filesystems

    install_base_packages
    configure_kernel
    configure_zram

    install_limine

    ui_log "Installation complete."
    ui_msg "Core installation finished.

You may reboot into your new system."
}

# ------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------

main() {

    screen_welcome

    screen_boot_mode

    screen_disk_selection

    screen_disk_mode

    screen_review

    if ui_confirm "Proceed with installation? This will modify disk structure."; then
        execute_installation
    else
        ui_msg "Installation cancelled safely."
        exit 0
    fi
}

main "$@"
