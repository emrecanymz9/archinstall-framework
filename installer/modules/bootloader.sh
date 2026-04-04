#!/usr/bin/env bash

BOOTLOADER_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$BOOTLOADER_MODULE_DIR/../boot/systemd-boot.sh" ]]; then
	# shellcheck source=installer/boot/systemd-boot.sh
	source "$BOOTLOADER_MODULE_DIR/../boot/systemd-boot.sh"
fi

if [[ -r "$BOOTLOADER_MODULE_DIR/../boot/grub.sh" ]]; then
	# shellcheck source=installer/boot/grub.sh
	source "$BOOTLOADER_MODULE_DIR/../boot/grub.sh"
fi

if [[ -r "$BOOTLOADER_MODULE_DIR/../boot/limine.sh" ]]; then
	# shellcheck source=installer/boot/limine.sh
	source "$BOOTLOADER_MODULE_DIR/../boot/limine.sh"
fi