#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Create GPT partition table (wipe mode)
# --------------------------------------------------
create_gpt_layout() {
    local disk="$1"

    # Create GPT label
    parted -s "$disk" mklabel gpt

    # EFI partition (550MB)
    parted -s "$disk" mkpart ESP fat32 1MiB 551MiB
    parted -s "$disk" set 1 esp on

    # Root partition (rest of disk)
    parted -s "$disk" mkpart ROOT 551MiB 100%

    EFI_PART="${disk}1"
    ROOT_PART="${disk}2"
}

# --------------------------------------------------
# Reuse existing ESP
# --------------------------------------------------
reuse_existing_esp() {
    local disk="$1"

    EFI_PART=$(lsblk -lpno NAME,FSTYPE "$disk" | awk '$2=="vfat"{print $1; exit}')
    ROOT_PART="$2"
}

# --------------------------------------------------
# Setup LUKS2 encryption
# --------------------------------------------------
setup_luks() {
    local part="$1"

    cryptsetup luksFormat --type luks2 "$part"
    cryptsetup open "$part" cryptroot

    ROOT_MAPPED="/dev/mapper/cryptroot"
}

# --------------------------------------------------
# Setup Btrfs filesystem
# --------------------------------------------------
setup_btrfs() {
    local target="$1"

    mkfs.btrfs -f -L ARCH "$target"

    mount "$target" /mnt

    # Create subvolumes
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots

    umount /mnt

    mount -o subvol=@,compress=zstd:-5 "$target" /mnt
    mkdir -p /mnt/{home,.snapshots,boot}
    mount -o subvol=@home,compress=zstd:-5 "$target" /mnt/home
    mount -o subvol=@snapshots,compress=zstd:-5 "$target" /mnt/.snapshots
}

# --------------------------------------------------
# Mount EFI
# --------------------------------------------------
mount_efi() {
    mkdir -p /mnt/boot
    mkfs.fat -F32 "$EFI_PART"
    mount "$EFI_PART" /mnt/boot
}

# --------------------------------------------------
# Install base system
# --------------------------------------------------
install_base() {
    pacstrap /mnt \
        base \
        base-devel \
        linux-zen \
        linux-zen-headers \
        linux-firmware \
        btrfs-progs \
        efibootmgr \
        networkmanager \
        vim \
        sudo \
        git

    genfstab -U /mnt >> /mnt/etc/fstab
}
