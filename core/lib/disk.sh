#!/usr/bin/env bash

# Requires:
# SELECTED_DISK
# DISK_MODE
# BOOT_MODE

PLAN_ROOT_PART=""
PLAN_EFI_PART=""

# ------------------------------------------------------------
# Planning
# ------------------------------------------------------------

plan_disk_layout() {

    if [[ "$DISK_MODE" == "entire" ]]; then
        PLAN_MODE="entire"
    elif [[ "$DISK_MODE" == "existing" ]]; then
        PLAN_MODE="existing"
        PLAN_ROOT_PART="$(ui_select_partition "$SELECTED_DISK")"
    else
        echo "Invalid disk mode"
        exit 1
    fi
}

# ------------------------------------------------------------
# Apply
# ------------------------------------------------------------

apply_disk_layout() {

    if [[ "$PLAN_MODE" == "entire" ]]; then
        wipefs -af "$SELECTED_DISK"

        if [[ "$BOOT_MODE" == "UEFI" ]]; then
            parted -s "$SELECTED_DISK" mklabel gpt
            parted -s "$SELECTED_DISK" mkpart ESP fat32 1MiB 513MiB
            parted -s "$SELECTED_DISK" set 1 esp on
            parted -s "$SELECTED_DISK" mkpart primary 513MiB 100%

            PLAN_EFI_PART="${SELECTED_DISK}1"
            PLAN_ROOT_PART="${SELECTED_DISK}2"

            mkfs.fat -F32 "$PLAN_EFI_PART"

        else
            parted -s "$SELECTED_DISK" mklabel msdos
            parted -s "$SELECTED_DISK" mkpart primary 1MiB 100%

            PLAN_ROOT_PART="${SELECTED_DISK}1"
        fi

    elif [[ "$PLAN_MODE" == "existing" ]]; then
        echo "Using existing partition: $PLAN_ROOT_PART"
    fi
}
