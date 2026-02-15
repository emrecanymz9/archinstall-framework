#!/usr/bin/env bash

setup_btrfs() {

    if [[ -z "$LUKS_DEVICE" ]]; then
        echo "LUKS device not opened"
        exit 1
    fi

    mkfs.btrfs -f "$LUKS_DEVICE"

    mount "$LUKS_DEVICE" /mnt

    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots

    umount /mnt
}

mount_filesystems() {

    mount -o compress=zstd:5,noatime,ssd,space_cache=v2,subvol=@ \
        "$LUKS_DEVICE" /mnt

    mkdir -p /mnt/{home,.snapshots,boot}

    mount -o compress=zstd:5,noatime,ssd,space_cache=v2,subvol=@home \
        "$LUKS_DEVICE" /mnt/home

    mount -o compress=zstd:5,noatime,ssd,space_cache=v2,subvol=@snapshots \
        "$LUKS_DEVICE" /mnt/.snapshots

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        mount "$PLAN_EFI_PART" /mnt/boot
    fi
}
