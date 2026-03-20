#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=installer/ui.sh
source "$SCRIPT_DIR/ui.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh"
# shellcheck source=installer/disk.sh
source "$SCRIPT_DIR/disk.sh"
# shellcheck source=installer/executor.sh
source "$SCRIPT_DIR/executor.sh"

show_state_summary() {
	local disk
	local efi_partition
	local root_partition

	disk="$(get_state "DISK" 2>/dev/null || printf 'Not selected')"
	efi_partition="$(get_state "EFI_PART" 2>/dev/null || printf 'Not created')"
	root_partition="$(get_state "ROOT_PART" 2>/dev/null || printf 'Not created')"

	msg "Installer State" "Saved state:\n\nDisk: $disk\nEFI: $efi_partition\nRoot: $root_partition" 12 76
}

show_disk_menu() {
	local choice
	local status

	while true; do
		choice="$(menu "Disk Setup" "Current disk: $(current_disk_label)" 16 76 6 \
			"select" "Discover disks and choose an install target" \
			"clear" "Clear the saved disk selection" \
			"back" "Return to the main menu")"
		status=$?

		case $status in
			0)
				;;
			1|255)
				return 0
				;;
			*)
				error_box "Navigation Error" "The disk menu returned an unexpected dialog status: $status"
				return "$status"
				;;
		esac

		case "$choice" in
			select)
				select_disk || true
				;;
			clear)
				unset_state "DISK"
				unset_state "EFI_PART"
				unset_state "ROOT_PART"
				msg "Disk Cleared" "The saved disk and partition state were removed."
				;;
			back)
				return 0
				;;
		esac
	done
}

show_install_menu() {
	local choice
	local status

	while true; do
		choice="$(menu "Install System" "Selected disk: $(current_disk_label)" 16 76 6 \
			"start" "Partition disk and install the base Arch Linux system" \
			"state" "Review the current installer state" \
			"back" "Return to the main menu")"
		status=$?

		case $status in
			0)
				;;
			1|255)
				return 0
				;;
			*)
				error_box "Navigation Error" "The install menu returned an unexpected dialog status: $status"
				return "$status"
				;;
		esac

		case "$choice" in
			start)
				install_base_system || true
				;;
			state)
				show_state_summary
				;;
			back)
				return 0
				;;
		esac
	done
}

main() {
	local choice
	local status

	require_dialog || exit $?
	ensure_state_file

	while true; do
		choice="$(menu "Main Menu" "Choose an installer action." 16 76 7 \
			"disk" "Disk setup and target selection" \
			"install" "Base system installation" \
			"state" "Show saved installer state" \
			"exit" "Exit the installer")"
		status=$?

		case $status in
			0)
				;;
			1|255)
				break
				;;
			*)
				error_box "Navigation Error" "The main menu returned an unexpected dialog status: $status"
				exit "$status"
				;;
		esac

		case "$choice" in
			disk)
				show_disk_menu
				;;
			install)
				show_install_menu
				;;
			state)
				show_state_summary
				;;
			exit)
				break
				;;
		esac
	done

	clear_screen
}

main "$@"