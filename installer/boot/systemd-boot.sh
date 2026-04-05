#!/usr/bin/env bash

detect_boot_mode() {
	if [[ -d /sys/firmware/efi ]]; then
		printf 'uefi\n'
		return 0
	fi

	printf 'bios\n'
}

bootloader_capability_value() {
	local bootloader=${1:?bootloader is required}
	local capability=${2:?capability is required}

	case "$bootloader:$capability" in
		systemd-boot:supports_uefi) printf 'true\n' ;;
		systemd-boot:supports_bios) printf 'false\n' ;;
		systemd-boot:supports_secure_boot) printf 'true\n' ;;
		systemd-boot:supports_uki) printf 'true\n' ;;
		systemd-boot:supports_luks2) printf 'true\n' ;;
		systemd-boot:complexity_level) printf 'simple\n' ;;
		systemd-boot:secure_boot_support_level) printf 'recommended\n' ;;
		grub:supports_uefi) printf 'true\n' ;;
		grub:supports_bios) printf 'true\n' ;;
		grub:supports_secure_boot) printf 'true\n' ;;
		grub:supports_uki) printf 'false\n' ;;
		grub:supports_luks2) printf 'true\n' ;;
		grub:complexity_level) printf 'advanced\n' ;;
		grub:secure_boot_support_level) printf 'limited\n' ;;
		limine:supports_uefi) printf 'true\n' ;;
		limine:supports_bios) printf 'true\n' ;;
		limine:supports_secure_boot) printf 'true\n' ;;
		limine:supports_uki) printf 'false\n' ;;
		limine:supports_luks2) printf 'true\n' ;;
		limine:complexity_level) printf 'advanced\n' ;;
		limine:secure_boot_support_level) printf 'advanced\n' ;;
		*) printf 'false\n' ;;
	esac
}

bootloader_short_description() {
	case ${1:-grub} in
		systemd-boot)
			printf 'Lean UEFI-first boot path with the cleanest UKI Secure Boot flow.\n'
			;;
		grub)
			printf 'Most compatible bootloader for BIOS and mixed-firmware installs, with a more complex Secure Boot path.\n'
			;;
		limine)
			printf 'Flexible bootloader for advanced BIOS or UEFI setups and manual recovery-oriented workflows.\n'
			;;
		*)
			printf 'Bootloader option\n'
			;;
	esac
}

bootloader_capability_badges() {
	local bootloader=${1:?bootloader is required}
	local uefi="-UEFI"
	local bios="-BIOS"
	local secure_boot="-SB"
	local uki="-UKI"
	local luks2="-LUKS2"

	[[ $(bootloader_capability_value "$bootloader" supports_uefi) == "true" ]] && uefi="+UEFI"
	[[ $(bootloader_capability_value "$bootloader" supports_bios) == "true" ]] && bios="+BIOS"
	[[ $(bootloader_capability_value "$bootloader" supports_secure_boot) == "true" ]] && secure_boot="+SB"
	[[ $(bootloader_capability_value "$bootloader" supports_uki) == "true" ]] && uki="+UKI"
	[[ $(bootloader_capability_value "$bootloader" supports_luks2) == "true" ]] && luks2="+LUKS2"
	printf '%s %s %s %s %s\n' "$uefi" "$bios" "$secure_boot" "$uki" "$luks2"
}

default_bootloader_for_mode() {
	local boot_mode=${1:-bios}
	local secure_boot_mode=${2:-disabled}

	if [[ $boot_mode == "uefi" && $secure_boot_mode != "disabled" ]]; then
		printf 'systemd-boot\n'
		return 0
	fi

	case $boot_mode in
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
	local secure_boot_mode=${3:-disabled}

	case $bootloader in
		systemd-boot|grub|limine)
			;;
		*)
			bootloader="$(default_bootloader_for_mode "$boot_mode" "$secure_boot_mode")"
			;;
	esac

	if [[ $boot_mode != "uefi" && $bootloader == "systemd-boot" ]]; then
		printf 'grub\n'
		return 0
	fi

	printf '%s\n' "$bootloader"
}

bootloader_is_selectable() {
	local bootloader=${1:?bootloader is required}
	local boot_mode=${2:-bios}
	local secure_boot_mode=${3:-disabled}
	local experience_level=${4:-simple}

	if [[ $boot_mode == "uefi" && $(bootloader_capability_value "$bootloader" supports_uefi) != "true" ]]; then
		return 1
	fi
	if [[ $boot_mode != "uefi" && $(bootloader_capability_value "$bootloader" supports_bios) != "true" ]]; then
		return 1
	fi
	if [[ $secure_boot_mode != "disabled" && $bootloader == "limine" && $experience_level != "advanced" ]]; then
		return 1
	fi
	return 0
}

bootloader_unavailable_reason() {
	local bootloader=${1:?bootloader is required}
	local boot_mode=${2:-bios}
	local secure_boot_mode=${3:-disabled}
	local experience_level=${4:-simple}

	if [[ $boot_mode == "uefi" && $(bootloader_capability_value "$bootloader" supports_uefi) != "true" ]]; then
		printf 'Requires UEFI firmware support.\n'
		return 0
	fi
	if [[ $boot_mode != "uefi" && $(bootloader_capability_value "$bootloader" supports_bios) != "true" ]]; then
		printf 'Requires BIOS support, which this bootloader does not provide.\n'
		return 0
	fi
	if [[ $secure_boot_mode != "disabled" && $bootloader == "limine" && $experience_level != "advanced" ]]; then
		printf 'Enable advanced mode to allow Limine with Secure Boot.\n'
		return 0
	fi
	printf '\n'
}

bootloader_selection_tag() {
	local bootloader=${1:-}
	local boot_mode=${2:-bios}
	local secure_boot_mode=${3:-disabled}
	local experience_level=${4:-simple}

	bootloader="$(normalize_bootloader "$bootloader" "$boot_mode" "$secure_boot_mode")"

	if ! bootloader_is_selectable "$bootloader" "$boot_mode" "$secure_boot_mode" "$experience_level"; then
		printf 'unavailable\n'
		return 0
	fi

	if [[ $secure_boot_mode != "disabled" && $bootloader == "systemd-boot" ]]; then
		printf 'recommended\n'
		return 0
	fi
	if [[ $boot_mode == "bios" && $bootloader == "grub" ]]; then
		printf 'recommended\n'
		return 0
	fi
	case $bootloader in
		systemd-boot)
			printf 'recommended\n'
			;;
		grub)
			printf 'advanced\n'
			;;
		limine)
			printf 'experimental\n'
			;;
		*)
			printf 'advanced\n'
			;;
	esac
}

bootloader_menu_description() {
	local bootloader=${1:?bootloader is required}
	local boot_mode=${2:-bios}
	local secure_boot_mode=${3:-disabled}
	local experience_level=${4:-simple}
	local tag="$(bootloader_selection_tag "$bootloader" "$boot_mode" "$secure_boot_mode" "$experience_level")"
	local badges="$(bootloader_capability_badges "$bootloader")"
	local description="$(bootloader_short_description "$bootloader")"
	local reason="$(bootloader_unavailable_reason "$bootloader" "$boot_mode" "$secure_boot_mode" "$experience_level")"

	case $tag in
		unavailable)
			printf '[unavailable] %s | %s | %s' "$description" "$badges" "${reason:-Not available}" 
			;;
		*)
			printf '[%s] %s | %s' "$tag" "$description" "$badges"
			;;
	esac
	printf '\n'
}

bootloader_guidance_text() {
	local boot_mode=${1:-bios}
	local secure_boot_mode=${2:-disabled}
	local experience_level=${3:-simple}

	printf 'Boot mode: %s\nSecure Boot: %s\nExperience level: %s\n\n' "$boot_mode" "$secure_boot_mode" "$experience_level"
	printf 'Selection rules:\n'
	printf '- BIOS disables systemd-boot\n'
	printf '- Secure Boot recommends systemd-boot with UKI\n'
	printf '- GRUB remains available but is more complex with Secure Boot\n'
	printf '- Limine with Secure Boot requires advanced mode\n\n'
	printf 'Compatibility:\n'
	printf 'systemd-boot: %s\n' "$(bootloader_capability_badges systemd-boot)"
	printf 'GRUB: %s\n' "$(bootloader_capability_badges grub)"
	printf 'Limine: %s\n' "$(bootloader_capability_badges limine)"
}

select_bootloader_value() {
	local boot_mode=${1:-bios}
	local secure_boot_mode=${2:-disabled}
	local _enable_luks=${3:-false}
	local current_bootloader=${4:-}
	local current_experience_level=${5:-simple}
	local -n bootloader_ref=${6:?bootloader reference is required}
	local -n experience_ref=${7:?experience reference is required}
	local selection=""
	local recommended="$(default_bootloader_for_mode "$boot_mode" "$secure_boot_mode")"
	local experience_level=${current_experience_level:-simple}

	bootloader_ref="$(normalize_bootloader "$current_bootloader" "$boot_mode" "$secure_boot_mode")"
	experience_ref=${experience_level:-simple}

	while true; do
		set_menu_default_item "${bootloader_ref:-$recommended}"
		menu "Bootloader" "Choose the bootloader.\n\nExample: choose systemd-boot for the simplest UEFI Secure Boot path.\nConstraint: unavailable combinations are shown but cannot be selected. Use Toggle Advanced to allow complex Secure Boot paths." 20 84 6 \
			"systemd-boot" "$(bootloader_menu_description systemd-boot "$boot_mode" "$secure_boot_mode" "$experience_level")" \
			"grub" "$(bootloader_menu_description grub "$boot_mode" "$secure_boot_mode" "$experience_level")" \
			"limine" "$(bootloader_menu_description limine "$boot_mode" "$secure_boot_mode" "$experience_level")" \
			"toggle-advanced" "Current mode: $experience_level. Toggle advanced boot options." \
			"details" "Show compatibility rules and rationale"
		selection="$DIALOG_RESULT"

		case $DIALOG_STATUS in
			1|255)
				return 1
				;;
			0)
				;;
			*)
				return 1
				;;
		esac

		case $selection in
			toggle-advanced)
				if [[ $experience_level == "advanced" ]]; then
					experience_level=simple
				else
					experience_level=advanced
				fi
				continue
				;;
			details)
				info_box "Bootloader Rules" "$(bootloader_guidance_text "$boot_mode" "$secure_boot_mode" "$experience_level")" 20 84
				continue
				;;
		esac

		if ! bootloader_is_selectable "$selection" "$boot_mode" "$secure_boot_mode" "$experience_level"; then
			warning_box "Bootloader Unavailable" "$(bootloader_unavailable_reason "$selection" "$boot_mode" "$secure_boot_mode" "$experience_level")\n\nSelected option: $(bootloader_label "$selection" "$boot_mode")"
			continue
		fi

		bootloader_ref="$selection"
		experience_ref="$experience_level"
		return 0
	done
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
