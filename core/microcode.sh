#!/usr/bin/env bash
set -euo pipefail

install_microcode() {
    if grep -qi intel /proc/cpuinfo; then
        arch-chroot /mnt pacman -S --noconfirm intel-ucode
    elif grep -qi amd /proc/cpuinfo; then
        arch-chroot /mnt pacman -S --noconfirm amd-ucode
    fi
}
