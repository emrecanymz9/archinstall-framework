#!/usr/bin/env bash

snapshot_provider_label() {
	case ${1:-none} in
		none)
			printf 'None\n'
			;;
		snapper)
			printf 'Snapper\n'
			;;
		timeshift)
			printf 'Timeshift\n'
			;;
		*)
			printf 'None\n'
			;;
	esac
}

snapshot_provider_details() {
	local provider=${1:-none}
	local bootloader=${2:-}

	case $provider in
		snapper)
			printf 'Snapper (preferred for %s)\n' "$(bootloader_label "$bootloader" "$(state_or_default "BOOT_MODE" "bios")")"
			;;
		timeshift)
			printf 'Timeshift (preferred for %s)\n' "$(bootloader_label "$bootloader" "$(state_or_default "BOOT_MODE" "bios")")"
			;;
		*)
			printf 'None\n'
			;;
	esac
}

normalize_snapshot_provider() {
	local provider=${1:-none}
	local filesystem=${2:-ext4}
	local bootloader=${3:-grub}

	case $provider in
		snapper)
			if [[ $filesystem == "btrfs" && $bootloader != "grub" ]]; then
				printf 'snapper\n'
				return 0
			fi
			printf 'none\n'
			return 0
			;;
		timeshift)
			if [[ $bootloader == "grub" ]]; then
				printf 'timeshift\n'
				return 0
			fi
			printf 'none\n'
			return 0
			;;
		*)
			printf 'none\n'
			return 0
			;;
	esac
}

snapshot_default_provider() {
	local filesystem=${1:-ext4}
	local bootloader=${2:-grub}

	if [[ $bootloader == "grub" ]]; then
		printf 'timeshift\n'
		return 0
	fi

	if [[ $filesystem == "btrfs" ]]; then
		printf 'snapper\n'
		return 0
	fi

	printf 'none\n'
}

snapshot_required_packages() {
	local provider=${1:-none}
	local filesystem=${2:-ext4}
	local boot_mode=${3:-uefi}
	local selected_bootloader=${4:-$(default_bootloader_for_mode "$boot_mode")}
	local -n package_ref=${5:?package reference is required}

	package_ref=()
	case $provider in
		snapper)
			if [[ $filesystem == "btrfs" ]]; then
				package_ref=(snapper snap-pac)
				if [[ $selected_bootloader == "grub" ]]; then
					package_ref+=(grub-btrfs)
				fi
			fi
			;;
		timeshift)
			package_ref=(timeshift)
			;;
		*)
			;;
	esac
}

snapshot_chroot_setup_snippet() {
	local provider=${1:-none}
	local filesystem=${2:-ext4}

	case $provider in
		snapper)
			if [[ $filesystem == "btrfs" ]]; then
				cat <<'EOF'
log_chroot_step "Configuring Snapper"
if command -v snapper >/dev/null 2>&1; then
	rm -rf /etc/snapper/configs/root /var/cache/snapper 2>/dev/null || true
	snapper -c root create-config / || true
	snapper -c root create -d "Initial system snapshot" || true
fi
EOF
			fi
			;;
		timeshift)
			cat <<'EOF'
log_chroot_step "Preparing Timeshift"
if command -v timeshift >/dev/null 2>&1; then
	install -d -m 0755 /etc/timeshift
	echo "[INFO] Timeshift installed. Initial snapshot policy can be configured after first boot."
fi
EOF
			;;
		*)
			;;
	esac
}

register_snapshots_module() {
	archinstall_register_module "snapshots" "Snapshot configuration support" "snapshot_chroot_setup_snippet"
}
