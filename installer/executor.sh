#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCHINSTALL_LOG=${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}
ARCHINSTALL_INSTALL_SUCCESS=${ARCHINSTALL_INSTALL_SUCCESS:-false}
ARCHINSTALL_CLEANUP_ACTIVE=${ARCHINSTALL_CLEANUP_ACTIVE:-false}

# shellcheck source=installer/ui.sh
source "$SCRIPT_DIR/ui.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh"

require_root() {
	if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
		return 0
	fi

	error_box "Root Required" "Run the installer as root from the Arch Linux live environment."
	return 1
}

require_commands() {
	local cmd
	local missing=()

	for cmd in dialog lsblk wipefs parted partprobe mkfs.fat mkfs.ext4 mount umount pacstrap genfstab ping reflector; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done

	if [[ ${#missing[@]} -eq 0 ]]; then
		return 0
	fi

	error_box "Missing Commands" "Install the required tools before continuing:\n\n${missing[*]}"
	return 1
}

partition_path() {
	local disk=${1:?disk is required}
	local number=${2:?partition number is required}

	case "$disk" in
		*nvme*|*mmcblk*)
			printf '%sp%s\n' "$disk" "$number"
			;;
		*)
			printf '%s%s\n' "$disk" "$number"
			;;
	esac
}

log_line() {
	local message=${1:-}

	printf '[%s] %s\n' "$(date '+%F %T')" "$message" >> "$ARCHINSTALL_LOG"
}

cleanup_mounts() {
	if mountpoint -q /mnt; then
		umount -R /mnt >> "$ARCHINSTALL_LOG" 2>&1 || return 1
	fi

	return 0
}

cleanup_install() {
	local reason=${1:-EXIT}

	if [[ ${ARCHINSTALL_CLEANUP_ACTIVE:-false} == true && ${ARCHINSTALL_INSTALL_SUCCESS:-false} != true ]]; then
		log_line "Cleanup triggered by $reason"
		cleanup_mounts || true
		ARCHINSTALL_CLEANUP_ACTIVE=false
	fi

	if [[ $reason == "INT" ]]; then
		exit 130
	fi
}

show_install_error() {
	local step=${1:-"Unknown step"}
	local excerpt

	excerpt="$(tail -n 12 "$ARCHINSTALL_LOG" 2>/dev/null || true)"
	error_box "Installation Failed" "Step failed: $step\n\nRecent log output:\n$excerpt"
}

run_step() {
	local step=${1:?step description is required}

	shift
	progress "Installing" "$step"
	log_line "$step"

	if "$@" >> "$ARCHINSTALL_LOG" 2>&1; then
		return 0
	fi

	show_install_error "$step"
	return 1
}

run_shell_step() {
	local step=${1:?step description is required}
	local command_string=${2:?command string is required}

	progress "Installing" "$step"
	log_line "$step"

	if bash -lc "$command_string" >> "$ARCHINSTALL_LOG" 2>&1; then
		return 0
	fi

	show_install_error "$step"
	return 1
}

run_step_with_retry() {
	local step=${1:?step description is required}
	local max_attempts=${2:?max attempts is required}
	local attempt=1

	shift 2

	while (( attempt <= max_attempts )); do
		progress "Installing" "$step\n\nAttempt $attempt/$max_attempts"
		log_line "$step (attempt $attempt/$max_attempts)"

		if "$@" >> "$ARCHINSTALL_LOG" 2>&1; then
			return 0
		fi

		if (( attempt == max_attempts )); then
			show_install_error "$step"
			return 1
		fi

		attempt=$((attempt + 1))
	done
}

install_base_system() {
	local disk=""
	local efi_partition=""
	local root_partition=""
	local confirm_status=0
	local install_status=0

	require_root || return 1
	require_commands || return 1

	disk="$(get_state "DISK" 2>/dev/null || true)"
	if [[ -z $disk ]]; then
		msg "Disk Required" "Select a target disk before starting the installation."
		return 1
	fi

	if [[ ! -b $disk ]]; then
		error_box "Invalid Disk" "The saved disk does not exist anymore:\n\n$disk"
		return 1
	fi

	confirm "Confirm Installation" "This will erase all data on:\n\n$disk\n\nand install a base Arch Linux system. Continue?" 12 76
	confirm_status=$?
	if [[ $confirm_status -ne 0 ]]; then
		return "$confirm_status"
	fi

	: > "$ARCHINSTALL_LOG" || {
		error_box "Log Error" "Could not write the install log:\n\n$ARCHINSTALL_LOG"
		return 1
	}

	if (
		ARCHINSTALL_INSTALL_SUCCESS=false
		ARCHINSTALL_CLEANUP_ACTIVE=true
		trap 'cleanup_install EXIT' EXIT
		trap 'cleanup_install INT' INT

		log_line "Starting base installation on $disk"
		run_step "Unmounting any previous install target" cleanup_mounts || exit 1
		run_step "Checking internet connectivity" ping -c 1 archlinux.org || exit 1
		run_step "Refreshing pacman mirrors" reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist || exit 1
		run_step "Wiping existing signatures on $disk" wipefs -a "$disk" || exit 1
		run_step "Creating a GPT partition table" parted -s "$disk" mklabel gpt || exit 1
		run_step "Creating the EFI system partition" parted -s "$disk" mkpart ESP fat32 1MiB 513MiB || exit 1
		run_step "Setting the EFI boot flag" parted -s "$disk" set 1 boot on || exit 1
		run_step "Setting the EFI ESP flag" parted -s "$disk" set 1 esp on || exit 1
		run_step "Creating the root partition" parted -s "$disk" mkpart ROOT ext4 513MiB 100% || exit 1
		run_step "Refreshing the kernel partition table" partprobe "$disk" || exit 1

		if command -v udevadm >/dev/null 2>&1; then
			run_step "Waiting for partition device nodes" udevadm settle || exit 1
		fi

		efi_partition="$(partition_path "$disk" 1)"
		root_partition="$(partition_path "$disk" 2)"

		if [[ ! -b $efi_partition || ! -b $root_partition ]]; then
			error_box "Partition Detection Failed" "Expected partitions were not created correctly:\n\n$efi_partition\n$root_partition"
			exit 1
		fi

		set_state "EFI_PART" "$efi_partition" || exit 1
		set_state "ROOT_PART" "$root_partition" || exit 1

		run_step "Formatting the EFI partition as FAT32" mkfs.fat -F32 "$efi_partition" || exit 1
		run_step "Formatting the root partition as ext4" mkfs.ext4 -F "$root_partition" || exit 1
		run_step "Mounting the root filesystem" mount "$root_partition" /mnt || exit 1
		run_step "Creating the EFI mount point" mkdir -p /mnt/boot || exit 1
		run_step "Mounting the EFI partition" mount "$efi_partition" /mnt/boot || exit 1
		run_step_with_retry "Installing the base Arch Linux packages" 3 pacstrap /mnt base linux linux-firmware || exit 1
		run_shell_step "Generating fstab" 'genfstab -U /mnt >> /mnt/etc/fstab' || exit 1

		ARCHINSTALL_INSTALL_SUCCESS=true
		ARCHINSTALL_CLEANUP_ACTIVE=false
		log_line "Base installation completed successfully"
		exit 0
	); then
		msg "Installation Complete" "Base Arch Linux packages were installed successfully.\n\nMounted target:\n/mnt\n\nNext step: install a bootloader and continue post-install configuration."
		return 0
	else
		install_status=$?
	fi

	return "$install_status"
}