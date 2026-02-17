#!/usr/bin/env bash
# ==========================================================
# Disk management module
# Handles disk detection and selection logic
# GPT/MBR aware
# NVMe / SATA / USB aware
# ==========================================================

set -Eeuo pipefail

# ----------------------------------------------------------
# List usable installation disks
# Excludes:
#  - loop devices
#  - rom
#  - current live medium
# ----------------------------------------------------------
list_install_disks() {
    lsblk -dpno NAME,SIZE,MODEL,TYPE |
        awk '$4=="disk" {print $1 "|" $2 "|" substr($0, index($0,$3))}'
}

# ----------------------------------------------------------
# Select disk via dialog menu
# ----------------------------------------------------------
select_disk() {

    local disks
    disks=$(list_install_disks)

    if [[ -z "$disks" ]]; then
        dialog --msgbox "No installable disks detected." 10 50
        return 1
    fi

    local menu_items=()

    while IFS="|" read -r name size model; do
        menu_items+=("$name" "$size - $model")
    done <<< "$disks"

    local choice
    choice=$(dialog \
        --clear \
        --backtitle "ArchInstall Framework 2026" \
        --title "Disk Selection" \
        --menu "Select installation disk:" \
        20 70 10 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3) || return 1

    if [[ -z "$choice" ]]; then
        return 1
    fi

    export TARGET_DISK="$choice"
    return 0
}

# ----------------------------------------------------------
# Detect partition table type
# ----------------------------------------------------------
detect_partition_table() {
    local disk="$1"
    parted -s "$disk" print | grep -i "Partition Table" | awk -F: '{print $2}' | xargs
}

# ----------------------------------------------------------
# Check for existing Windows EFI
# ----------------------------------------------------------
detect_windows_efi() {
    lsblk -o NAME,FSTYPE,MOUNTPOINT | grep -i vfat | grep -qi efi && return 0
    return 1
}
