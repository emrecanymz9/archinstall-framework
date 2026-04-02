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
			printf '%s\n' "$1"
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
	local -n package_ref=${4:?package reference is required}

	package_ref=()
	case $provider in
		snapper)
			if [[ $filesystem == "btrfs" ]]; then
				package_ref=(snapper snap-pac)
				# grub-btrfs provides btrfs snapshot entries in the GRUB menu.
				# It is only meaningful when GRUB is the bootloader (BIOS installs).
				# For systemd-boot (UEFI), btrfs snapshots are navigated differently.
				if [[ $boot_mode == "bios" ]]; then
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
	systemctl enable snapper-timeline.timer snapper-cleanup.timer || true
	snapper -c root create -d "Initial system snapshot" || true
fi
EOF
			fi
			;;
		timeshift)
			cat <<'EOF'
log_chroot_step "Configuring Timeshift"
if command -v timeshift >/dev/null 2>&1; then
	timeshift --create --comments "Initial system snapshot" --tags D || true
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