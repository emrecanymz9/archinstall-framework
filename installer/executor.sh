#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCHINSTALL_LOG=${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}

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

	for cmd in dialog lsblk wipefs parted partprobe mkfs.fat mkfs.ext4 mount umount pacstrap genfstab arch-chroot; do
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

cleanup_mounts() {
	if mountpoint -q /mnt; then
		umount -R /mnt >> "$ARCHINSTALL_LOG" 2>&1 || return 1
	fi

	return 0
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

	if bash -lc "$command_string" >> "$ARCHINSTALL_LOG" 2>&1; then
		return 0
	fi

	show_install_error "$step"
	return 1
}

install_base_system() {
	local disk
	local efi_partition
	local root_partition
	local success=0

	require_root || return 1
	require_commands || return 1

	if ! disk="$(get_state "DISK" 2>/dev/null)"; then
		msg "Disk Required" "Select a target disk before starting the installation."
		return 1
	fi

	if [[ ! -b $disk ]]; then
		error_box "Invalid Disk" "The saved disk does not exist anymore:\n\n$disk"
		return 1
	fi

	if ! confirm "Confirm Installation" "This will erase all data on:\n\n$disk\n\nand install a base Arch Linux system. Continue?" 12 76; then
		return 1
	fi

	: > "$ARCHINSTALL_LOG"
	trap 'if [[ $success -eq 0 ]]; then cleanup_mounts || true; fi' RETURN

	run_step "Unmounting any previous install target" cleanup_mounts || return 1
	run_step "Wiping existing signatures on $disk" wipefs -af "$disk" || return 1
	run_step "Creating a GPT partition table" parted -s "$disk" mklabel gpt || return 1
	run_step "Creating the EFI system partition" parted -s "$disk" mkpart ESP fat32 1MiB 513MiB || return 1
	run_step "Flagging the EFI partition" parted -s "$disk" set 1 esp on || return 1
	run_step "Creating the root partition" parted -s "$disk" mkpart ROOT ext4 513MiB 100% || return 1
	run_step "Refreshing the kernel partition table" partprobe "$disk" || return 1

	if command -v udevadm >/dev/null 2>&1; then
		run_step "Waiting for partition device nodes" udevadm settle || return 1
	fi

	efi_partition="$(partition_path "$disk" 1)"
	root_partition="$(partition_path "$disk" 2)"

	if [[ ! -b $efi_partition || ! -b $root_partition ]]; then
		error_box "Partition Detection Failed" "Expected partitions were not created correctly:\n\n$efi_partition\n$root_partition"
		return 1
	fi

	set_state "EFI_PART" "$efi_partition"
	set_state "ROOT_PART" "$root_partition"

	run_step "Formatting the EFI partition as FAT32" mkfs.fat -F32 "$efi_partition" || return 1
	run_step "Formatting the root partition as ext4" mkfs.ext4 -F "$root_partition" || return 1
	run_step "Mounting the root filesystem" mount "$root_partition" /mnt || return 1
	run_step "Creating the EFI mount point" mkdir -p /mnt/boot || return 1
	run_step "Mounting the EFI partition" mount "$efi_partition" /mnt/boot || return 1
	run_step "Installing the base Arch Linux packages" pacstrap -K /mnt base linux linux-firmware dialog networkmanager || return 1
	run_shell_step "Generating fstab" 'genfstab -U /mnt >> /mnt/etc/fstab' || return 1
	run_step "Enabling NetworkManager in the new system" arch-chroot /mnt systemctl enable NetworkManager || return 1

	success=1
	trap - RETURN
	msg "Installation Complete" "Base Arch Linux packages were installed successfully.\n\nMounted target:\n/mnt\n\nNext step: install a bootloader and run post-install configuration."
	return 0
}