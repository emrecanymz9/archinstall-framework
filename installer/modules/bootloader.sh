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

bootloader_common_chroot_snippet() {
	cat <<'EOF'
build_kernel_cmdline() {
	local kernel_cmdline=""

	if [[ $TARGET_LUKS_ENABLED == "true" && -n ${LUKS_UUID:-} ]]; then
		kernel_cmdline="cryptdevice=UUID=$LUKS_UUID:$TARGET_LUKS_MAPPER_NAME root=UUID=$ROOT_UUID rw"
	else
		kernel_cmdline="root=UUID=$ROOT_UUID rw"
	fi

	if [[ $TARGET_FILESYSTEM == "btrfs" ]]; then
		kernel_cmdline="$kernel_cmdline rootfstype=btrfs rootflags=$TARGET_ROOT_MOUNT_OPTIONS"
	fi
	if [[ $TARGET_GPU_VENDOR == "nvidia" ]]; then
		kernel_cmdline="$kernel_cmdline nvidia_drm.modeset=1"
	fi

	printf '%s\n' "$kernel_cmdline"
}
EOF
}