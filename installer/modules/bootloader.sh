#!/usr/bin/env bash

detect_boot_mode() {
	if [[ -d /sys/firmware/efi/efivars || -d /sys/firmware/efi ]]; then
		printf 'uefi\n'
		return 0
	fi

	printf 'bios\n'
}