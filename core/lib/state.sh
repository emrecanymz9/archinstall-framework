#!/usr/bin/env bash

# Global state variables

BOOT_MODE=""
SELECTED_DISK=""
DISK_MODE=""        # entire | existing
TARGET_PARTITION=""
ROOT_UUID=""

# ------------------------------------------------------------
# Boot detection
# ------------------------------------------------------------

detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
}

# ------------------------------------------------------------
# Disk selection
# ------------------------------------------------------------

select_disk() {
    SELECTED_DISK="$(ui_select_disk)"
}

select_disk_mode() {
    DISK_MODE="$(ui_select_disk_mode)"
}

# ------------------------------------------------------------
# Review
# ------------------------------------------------------------

ui_review_summary() {
    ui_msg "Installation Plan:

Boot Mode:      $BOOT_MODE
Disk:           $SELECTED_DISK
Disk Mode:      $DISK_MODE
Filesystem:     Btrfs (zstd:5)
Encryption:     LUKS2
Kernel:         linux-zen
Swap:           ZRAM
Bootloader:     Limine"
}
