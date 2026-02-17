#!/usr/bin/env bash
set -euo pipefail

install_limine() {

    arch-chroot /mnt pacman -S --noconfirm limine

    mkdir -p /mnt/boot/EFI/Limine

    arch-chroot /mnt limine-install

    efibootmgr -c \
        -d "$TARGET_DISK" \
        -p 1 \
        -L "Arch Linux (Limine)" \
        -l '\EFI\Limine\limine.efi'
}
