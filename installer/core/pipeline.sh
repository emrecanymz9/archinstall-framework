#!/usr/bin/env bash

apply_disk() {
	log_line "Starting installation on $disk"
	log_line "Install scenario: $install_scenario"

	if [[ -z $disk || ! -b $disk ]]; then
		print_install_error "Disk validation failed: '${disk:-unset}' is not a valid block device."
		log_line "[FAIL] apply_disk: invalid disk '${disk:-unset}'"
		return 1
	fi

	disk_type="$(normalize_disk_type "$(detect_disk_type "$disk")")"
	set_state "DISK_MODEL" "$(disk_model_value "$disk")" || return 1
	set_state "DISK_TRANSPORT" "$(disk_transport_value "$disk")" || return 1
	set_state "DISK_TYPE" "$disk_type" || return 1
	log_line "Disk type: $disk_type"

	run_step "Unmounting any previous install target" cleanup_mounts || return 1

	if mountpoint -q /mnt 2>/dev/null; then
		print_install_error "/mnt is still mounted after cleanup. Cannot proceed with disk operations."
		log_line "[FAIL] apply_disk: /mnt still mounted after cleanup_mounts"
		return 1
	fi

	if [[ -d /mnt/etc || -d /mnt/boot ]]; then
		print_install_error "/mnt contains previous installation data (/mnt/etc or /mnt/boot). Clean /mnt before retrying."
		log_line "[FAIL] /mnt is not clean: refusing to proceed"
		return 1
	fi

	if flag_enabled "$SKIP_PARTITION"; then
		log_line "Skipping partitioning and formatting because SKIP_PARTITION=$SKIP_PARTITION"
	elif [[ $install_scenario != "wipe" ]]; then
		log_line "Reusing prepared partition layout because INSTALL_SCENARIO=$install_scenario"
	else
		log_stage 15 "Partitioning disk"
		run_step "Wiping existing signatures on $disk" wipefs -a "$disk" || return 1
		if [[ $boot_mode == "uefi" ]]; then
			run_step "Creating a GPT partition table" parted -s "$disk" mklabel gpt || return 1
			run_step "Creating the EFI system partition" parted -s "$disk" mkpart ESP fat32 1MiB 1025MiB || return 1
			run_step "Setting the EFI boot flag" parted -s "$disk" set 1 boot on || return 1
			run_step "Setting the EFI ESP flag" parted -s "$disk" set 1 esp on || return 1
			run_step "Creating the root partition" parted -s "$disk" mkpart ROOT ext4 1025MiB 100% || return 1
		else
			run_step "Creating an MBR partition table" parted -s "$disk" mklabel msdos || return 1
			run_step "Creating the root partition" parted -s "$disk" mkpart primary ext4 1MiB 100% || return 1
			run_step "Marking the root partition bootable" parted -s "$disk" set 1 boot on || return 1
		fi
		run_step "Refreshing the kernel partition table" partprobe "$disk" || return 1
		if command -v udevadm >/dev/null 2>&1; then
			run_step "Waiting for partition device nodes" udevadm settle || return 1
		fi
	fi

	mapfile -t resolved_partitions < <(resolve_target_partitions "$disk" "$boot_mode") || return 1
	efi_partition=${resolved_partitions[0]:-}
	root_partition=${resolved_partitions[1]:-}
	[[ $efi_partition == "-" ]] && efi_partition=""

	if [[ -z $root_partition ]]; then
		print_install_error "Could not resolve the target partitions for: $disk"
		return 1
	fi
	if [[ $boot_mode == "uefi" && -z $efi_partition ]]; then
		print_install_error "Could not resolve the EFI partition for: $disk"
		return 1
	fi

	if [[ -n $efi_partition ]]; then
		set_state "EFI_PART" "$efi_partition" || return 1
	else
		unset_state "EFI_PART" || return 1
	fi
	set_state "ROOT_PART" "$root_partition" || return 1

	log_stage 25 "Mounting filesystems"
	if flag_enabled "$SKIP_PARTITION"; then
		log_line "Skipping filesystem creation because SKIP_PARTITION=$SKIP_PARTITION"
	else
		if [[ $boot_mode == "uefi" && $format_efi == "true" ]]; then
			run_step "Formatting the EFI partition as FAT32" mkfs.fat -F32 "$efi_partition" || return 1
		fi
		if [[ $format_root == "true" ]]; then
			if flag_enabled "$enable_luks"; then
				root_mount_device="$(prepare_luks_root_device "$root_partition" "$luks_mapper_name" "${INSTALL_LUKS_PASSWORD:-}")" || return 1
				set_state "ROOT_MAPPER" "$root_mount_device" || return 1
				luks_partition_uuid="$(get_partition_uuid "$root_partition")" || return 1
				set_state "LUKS_PART_UUID" "$luks_partition_uuid" || return 1
				format_root_filesystem "$filesystem" "$root_mount_device" || return 1
			else
				root_mount_device="$root_partition"
				format_root_filesystem "$filesystem" "$root_partition" || return 1
			fi
		else
			log_line "Skipping root filesystem creation because FORMAT_ROOT=$format_root"
		fi
	fi

	if [[ -z $root_mount_device ]]; then
		if flag_enabled "$enable_luks"; then
			root_mount_device="$(open_luks_root_device "$root_partition" "$luks_mapper_name" "${INSTALL_LUKS_PASSWORD:-}")" || return 1
			set_state "ROOT_MAPPER" "$root_mount_device" || return 1
			if [[ -z ${luks_partition_uuid:-} ]]; then
				luks_partition_uuid="$(get_partition_uuid "$root_partition")" || return 1
				set_state "LUKS_PART_UUID" "$luks_partition_uuid" || return 1
			fi
		else
			root_mount_device="$root_partition"
		fi
	fi

	mount_root_filesystem "$filesystem" "$disk_type" "$root_mount_device" || return 1
	validate_target_mount "$root_mount_device" || return 1
	expected_root_source="$(normalized_mount_source /mnt)"
	if [[ -z $expected_root_source ]]; then
		print_install_error "Could not determine the expected source for /mnt after mounting."
		return 1
	fi
	log_line "[DEBUG] Locked /mnt to expected source: $expected_root_source"
	log_line "[DEBUG] Mount state after root mount"
	log_mount_state
	if [[ $boot_mode == "uefi" ]]; then
		validate_target_mount "$root_mount_device" "$expected_root_source" || return 1
		run_step "Creating the EFI mount point" mkdir -p /mnt/boot || return 1
		run_step "Mounting the EFI partition" mount "$efi_partition" /mnt/boot || return 1
	fi
	validate_target_mount "$root_mount_device" "$expected_root_source" || return 1
	log_partition_metadata "$root_partition" "$efi_partition"
	log_mounted_filesystems "$filesystem"
	required_space_mib="$(estimate_target_required_space_mib "$desktop_profile" "$filesystem")"
	validate_target_mount "$root_mount_device" "$expected_root_source" || return 1
	run_step "Checking target free space" ensure_target_has_space /mnt "$required_space_mib" || return 1
}

apply_base() {
	log_stage 5 "Checking prerequisites"
	run_optional_step "Checking internet connectivity" ping -c 1 archlinux.org
	initialize_pacman_environment || return 1
	if [[ $install_steam == "true" ]]; then
		run_step "Enabling multilib for Steam support" enable_multilib_repo /etc/pacman.conf || return 1
	fi

	if flag_enabled "$SKIP_PACSTRAP"; then
		log_line "Skipping pacstrap because SKIP_PACSTRAP=$SKIP_PACSTRAP"
		if ! verify_target_system_present "$root_mount_device" "$expected_root_source"; then
			print_install_error "SKIP_PACSTRAP=true requires an existing installed system mounted at /mnt."
			return 1
		fi
		verify_base_system_files "$root_mount_device" "$expected_root_source" || return 1
		log_installed_target_packages "$root_mount_device" "$expected_root_source" || return 1
	else
		validate_target_mount "$root_mount_device" "$expected_root_source" || return 1
		log_stage 35 "Downloading and installing packages (this may take several minutes)"
		run_optional_step "Removing legacy iptables to prevent conflict" pacman -Rdd iptables --noconfirm
		run_pacstrap_install "${pacstrap_packages[@]}" || return 1
		log_line "[DEBUG] Mount state after pacstrap"
		log_mount_state
		validate_target_mount "$root_mount_device" "$expected_root_source" || return 1
		verify_target_system_present "$root_mount_device" "$expected_root_source" || return 1
		verify_base_system_files "$root_mount_device" "$expected_root_source" || return 1
		log_line "[DEBUG] Verified required base system files after pacstrap"
		log_installed_target_packages "$root_mount_device" "$expected_root_source" || return 1
	fi

	log_stage 82 "Generating fstab"
	postinstall_generate_fstab "$filesystem" "$disk_type" "$root_mount_device" "$expected_root_source" "$efi_partition" || return 1
}

apply_gpu() {
	refresh_gpu_install_state >/dev/null 2>&1 || true
	gpu_vendor="$(get_state "GPU_VENDOR" 2>/dev/null || printf 'generic')"
	log_line "GPU: $(gpu_vendor_label "$gpu_vendor")"
}

apply_display() {
	apply_display_state "$desktop_profile" display_session display_manager greeter || return 1
	resolved_display_session="$(state_or_default "DISPLAY_SESSION" "$(normalize_display_session "$display_session")")"
	log_line "Desktop profile: $desktop_profile"
	log_line "Display session: $resolved_display_session"
	log_line "Display manager: $display_manager"
	log_line "Greeter: $greeter"
}

apply_boot() {
	bootloader="$(normalize_bootloader "$bootloader" "$boot_mode")"
	set_state "BOOT_MODE" "$boot_mode" || return 1
	set_state "BOOTLOADER" "$bootloader" || return 1
	log_line "Boot mode: $boot_mode"
	log_line "Bootloader: $(bootloader_label "$bootloader" "$boot_mode")"
}

apply_features() {
	set_state "ENABLE_LUKS" "$enable_luks" || return 1
	set_state "LUKS_MAPPER_NAME" "$luks_mapper_name" || return 1
	set_state "SNAPSHOT_PROVIDER" "$snapshot_provider" || return 1
	set_state "SECURE_BOOT_MODE" "$secure_boot_mode" || return 1
	log_line "Secure Boot firmware state: $current_secure_boot_state"
	log_line "Secure Boot mode: $secure_boot_mode"
	log_line "Filesystem: $filesystem"
	log_line "Encryption: $enable_luks"
	log_line "Snapshot provider: $snapshot_provider"
	log_line "Steam: $install_steam"
	log_line "Safe mode: $INSTALL_SAFE_MODE"
	if flag_enabled "$DEV_MODE"; then
		log_line "DEV_MODE enabled: SKIP_PARTITION=$SKIP_PARTITION SKIP_PACSTRAP=$SKIP_PACSTRAP SKIP_CHROOT=$SKIP_CHROOT"
	fi
}

apply_postinstall() {
	local log_username
	local manifest_path

	if flag_enabled "$SKIP_CHROOT"; then
		log_line "Skipping chroot configuration because SKIP_CHROOT=$SKIP_CHROOT"
	else
		validate_target_mount "$root_mount_device" "$expected_root_source" || return 1
		root_uuid="$(get_partition_uuid "$root_mount_device")" || return 1
		if [[ $filesystem == "btrfs" ]]; then
			root_mount_options="$(btrfs_mount_options '@' "$disk_type")"
		else
			root_mount_options=""
		fi
		prepare_chroot_mounts "$root_mount_device" "$expected_root_source" || return 1
		log_stage 88 "Running chroot configuration"
		run_chroot_configuration "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$root_mount_options" "$enable_zram" "$desktop_profile" "$display_manager" "$display_session" "$resolved_display_session" "$root_mount_device" "$expected_root_source" || return 1
		log_stage 95 "Finalizing installation"
		if type run_hooks >/dev/null 2>&1; then
			run_hooks post_chroot "$disk" "$root_partition" || true
		fi
	fi

	log_username="$(get_state "USERNAME" 2>/dev/null || printf 'archuser')"
	if type export_install_logs_to_target >/dev/null 2>&1; then
		export_install_logs_to_target "$ARCHINSTALL_LOG" "$log_username" || true
		log_line "Install log exported to /var/log/archinstall.log and /home/$log_username/install.log"
	fi

	manifest_path="/mnt/home/$log_username/archinstall-manifest.txt"
	if [[ -n $log_username && -d "/mnt/home/$log_username" ]]; then
		{
			printf 'ArchInstall Framework — Install Manifest\n'
			printf 'Generated: %s\n' "$(date '+%F %T')"
			printf '========================================\n\n'
			printf 'CONFIGURATION\n'
			printf '-------------\n'
			printf 'Hostname    : %s\n' "$(get_state "HOSTNAME" 2>/dev/null || printf 'unknown')"
			printf 'Timezone    : %s\n' "$(get_state "TIMEZONE" 2>/dev/null || printf 'unknown')"
			printf 'Locale      : %s\n' "$(get_state "LOCALE" 2>/dev/null || printf 'unknown')"
			printf 'Keymap      : %s\n' "$(get_state "KEYMAP" 2>/dev/null || printf 'unknown')"
			printf 'User        : %s\n' "$log_username"
			printf 'Profile     : %s\n' "$(get_state "INSTALL_PROFILE" 2>/dev/null || printf 'unknown')"
			printf 'Desktop     : %s\n' "$(get_state "DESKTOP_PROFILE" 2>/dev/null || printf 'none')"
			printf 'Display Mgr : %s\n' "$(get_state "DISPLAY_MANAGER" 2>/dev/null || printf 'none')"
			printf 'Bootloader  : %s\n' "$(get_state "BOOTLOADER" 2>/dev/null || printf 'unknown')"
			printf 'Filesystem  : %s\n' "$filesystem"
			printf 'Encryption  : %s\n' "$enable_luks"
			printf 'Snapshots   : %s\n' "$snapshot_provider"
			printf 'Steam       : %s\n' "$install_steam"
			printf 'Zram        : %s\n' "$enable_zram"
			printf 'Boot Mode   : %s\n' "$boot_mode"
			printf 'Secure Boot : %s\n' "$secure_boot_mode"
			printf 'CPU Vendor  : %s\n' "$(get_state "CPU_VENDOR" 2>/dev/null || printf 'unknown')"
			printf 'GPU Vendor  : %s\n' "$(get_state "GPU_VENDOR" 2>/dev/null || printf 'unknown')"
			printf 'Environment : %s\n' "$(get_state "ENVIRONMENT_VENDOR" 2>/dev/null || printf 'unknown')"
			printf '\nDISK LAYOUT\n'
			printf '-----------\n'
			printf 'Device      : %s\n' "$disk"
			printf 'Disk Model  : %s\n' "$(get_state "DISK_MODEL" 2>/dev/null || printf 'unknown')"
			printf 'Disk Bus    : %s\n' "$(get_state "DISK_TRANSPORT" 2>/dev/null || printf 'unknown')"
			printf 'Disk Type   : %s\n' "$disk_type"
			printf 'Scenario    : %s\n' "$(get_state "INSTALL_SCENARIO" 2>/dev/null || printf 'wipe')"
			printf 'EFI         : %s\n' "${efi_partition:-not required}"
			printf 'Root        : %s\n' "$root_partition"
			printf '\nPartition table:\n'
			lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$disk" 2>/dev/null || printf '  (lsblk unavailable)\n'
			printf '\nMOUNT POINTS\n'
			printf '------------\n'
			findmnt -R /mnt 2>/dev/null || printf '  (findmnt unavailable)\n'
			printf '\nPACKAGES INSTALLED\n'
			printf '------------------\n'
			timeout 300 arch-chroot /mnt pacman -Q 2>/dev/null || printf '  (unavailable)\n'
		} > "$manifest_path" 2>/dev/null || true
		chmod 644 "$manifest_path" 2>/dev/null || true
		log_line "Install manifest saved to $manifest_path"
	fi
}

run_install_pipeline() {
	apply_disk || return 1
	apply_base || return 1
	apply_gpu || return 1
	apply_display || return 1
	apply_boot || return 1
	apply_features || return 1
	apply_postinstall || return 1
	return 0
}