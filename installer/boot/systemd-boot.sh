#!/usr/bin/env bash

detect_boot_mode() {
	if [[ -d /sys/firmware/efi ]]; then
		printf 'uefi\n'
		return 0
	fi

	printf 'bios\n'
}

default_bootloader_for_mode() {
	case ${1:-bios} in
		uefi)
			printf 'systemd-boot\n'
			;;
		*)
			printf 'grub\n'
			;;
	esac
}

normalize_bootloader() {
	local bootloader=${1:-}
	local boot_mode=${2:-$(detect_boot_mode 2>/dev/null || printf 'bios')}

	case $bootloader in
		systemd-boot|grub|limine)
			;;
		*)
			bootloader="$(default_bootloader_for_mode "$boot_mode")"
			;;
	esac

	if [[ $boot_mode != "uefi" && $bootloader == "systemd-boot" ]]; then
		printf 'grub\n'
		return 0
	fi

	printf '%s\n' "$bootloader"
}

bootloader_label() {
	case $(normalize_bootloader "${1:-}" "${2:-bios}") in
		systemd-boot)
			printf 'systemd-boot\n'
			;;
		grub)
			printf 'GRUB\n'
			;;
		limine)
			printf 'Limine\n'
			;;
		*)
			printf 'GRUB\n'
			;;
	esac
}

bootloader_required_packages() {
	local bootloader="$(normalize_bootloader "${1:-}" "${2:-bios}")"
	local boot_mode=${2:-bios}
	local -n package_ref=${3:?package reference is required}

	package_ref=()
	case $bootloader in
		grub)
			package_ref+=(grub)
			if [[ $boot_mode == "uefi" ]]; then
				package_ref+=(efibootmgr)
			fi
			;;
		limine)
			package_ref+=(limine)
			;;
		*)
			;;
	esac
}

bootloader_required_commands() {
	local bootloader="$(normalize_bootloader "${1:-}" "${2:-bios}")"
	local boot_mode=${2:-bios}
	local -n command_ref=${3:?command reference is required}

	command_ref=()
	case $bootloader in
		systemd-boot)
			if [[ $boot_mode == "uefi" ]]; then
				command_ref+=(bootctl)
			fi
			;;
		grub)
			command_ref+=(grub-install grub-mkconfig)
			;;
		limine)
			command_ref+=(limine)
			;;
		*)
			;;
	esac
}

systemd_boot_chroot_snippet() {
	cat <<'EOF'
log_chroot_step "Installing systemd-boot"
bootctl install
mkdir -p /boot/loader/entries

MICROCODE_INITRD_LINE=""
if [[ -f /boot/intel-ucode.img ]]; then
	MICROCODE_INITRD_LINE="initrd /intel-ucode.img"
elif [[ -f /boot/amd-ucode.img ]]; then
	MICROCODE_INITRD_LINE="initrd /amd-ucode.img"
fi

if [[ $TARGET_SECURE_BOOT_MODE == "disabled" ]]; then
	cat > /boot/loader/loader.conf <<'LOADERCONF'
default arch
timeout 3
editor no
LOADERCONF
else
	cat > /boot/loader/loader.conf <<'LOADERCONF'
default @saved
timeout 3
editor no
LOADERCONF
fi

{
	echo "title Arch Linux"
	echo "linux /vmlinuz-linux"
	[[ -n "$MICROCODE_INITRD_LINE" ]] && echo "$MICROCODE_INITRD_LINE"
	echo "initrd /initramfs-linux.img"
	echo "options $(build_kernel_cmdline)"
} > /boot/loader/entries/arch.conf

echo "[DEBUG] systemd-boot arch.conf:"
cat /boot/loader/entries/arch.conf
EOF
}

emit_bootloader_chroot_snippet() {
	local bootloader="$(normalize_bootloader "${1:-}" "${2:-bios}")"
	local boot_mode=${2:-bios}

	case $bootloader in
		systemd-boot)
			systemd_boot_chroot_snippet
			;;
		grub)
			grub_chroot_snippet "$boot_mode"
			;;
		limine)
			limine_chroot_snippet "$boot_mode"
			;;
		*)
			grub_chroot_snippet "$boot_mode"
			;;
	esac
}
