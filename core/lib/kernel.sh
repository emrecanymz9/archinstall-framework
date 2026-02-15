#!/usr/bin/env bash

install_base_packages() {

    pacstrap /mnt \
        base \
        linux-zen \
        linux-zen-headers \
        linux-firmware \
        btrfs-progs \
        networkmanager \
        openssh \
        limine
}

configure_kernel() {

    genfstab -U /mnt >> /mnt/etc/fstab

    arch-chroot /mnt mkinitcpio -P
}
