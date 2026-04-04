#!/usr/bin/env bash

snapshot_provider_label() {
	case ${1:-none} in
		none)
			printf 'None\n'
			;;
		snapper)
			printf 'Snapper\n'
			;;
		*)
			printf 'None\n'
			;;
	esac
}

snapshot_default_provider() {
	local filesystem=${1:-ext4}
	local install_profile=${2:-daily}

	if [[ $filesystem == "btrfs" && $install_profile == "daily" ]]; then
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
		*)
			;;
	esac
}

register_snapshots_module() {
	archinstall_register_module "snapshots" "Snapshot configuration support" "snapshot_chroot_setup_snippet"
}
