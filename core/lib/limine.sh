#!/usr/bin/env bash

install_limine() {

    ROOT_UUID=$(blkid -s UUID -o value "$PLAN_ROOT_PART")

    arch-chroot /mnt limine-install "$SELECTED_DISK"

    mkdir -p /mnt/boot/EFI/limine || true

    cat <<EOF > /mnt/boot/limine.cfg
TIMEOUT=5
DEFAULT_ENTRY=Arch Linux

:Arch Linux
    PROTOCOL=linux
    KERNEL_PATH=/boot/vmlinuz-linux-zen
    INITRD_PATH=/boot/initramfs-linux-zen.img
    CMDLINE=root=UUID=$ROOT_UUID rw
EOF
}
