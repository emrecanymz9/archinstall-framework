#!/usr/bin/env bash

configure_zram() {

    arch-chroot /mnt pacman -S --noconfirm zram-generator

    cat <<EOF > /mnt/etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

    arch-chroot /mnt systemctl enable systemd-zram-setup@zram0.service
}
