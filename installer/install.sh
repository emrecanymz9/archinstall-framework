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

confirm_installation() {
	local disk=""
	local message=""

	require_root || return 1

	disk="$(get_state "DISK" 2>/dev/null || true)"
	if [[ -z $disk ]]; then
		msg "Disk Required" "Select a target disk before starting the installation."
		return 1
	fi

	if [[ ! -b $disk ]]; then
		error_box "Invalid Disk" "The saved disk does not exist anymore:\n\n$disk"
		return 1
	fi

	message="This will prepare a bootable Arch Linux system on:\n\n$disk\n\nDestructive steps may erase existing data."
	if flag_enabled "$DEV_MODE"; then
		message+="\n\nDev mode flags:\nSKIP_PARTITION=$SKIP_PARTITION\nSKIP_PACSTRAP=$SKIP_PACSTRAP\nSKIP_CHROOT=$SKIP_CHROOT\nINSTALL_UI_MODE=$INSTALL_UI_MODE"
	fi

	confirm "Confirm Installation" "$message\n\nContinue?" 18 76
}

run_install() {
	local status=0
	local prompt_status=0
	local skip_confirm=false

	confirm_installation
	prompt_status=$?
	if [[ $prompt_status -ne 0 ]]; then
		return "$prompt_status"
	fi

	clear
	if command -v tput >/dev/null 2>&1; then
		tput cnorm || true
	fi

	echo "[*] Starting Arch installation..."
	echo "[*] This may take a while..."
	echo

	skip_confirm=true
	install_base_system "$skip_confirm"
	status=$?

	echo
	case $status in
		0)
			echo "[✓] Installation finished successfully"
			;;
		130)
			echo "[!] Installation interrupted"
			;;
		*)
			echo "[!] Installation finished with errors (status: $status)"
			;;
	esac
	echo "[*] Log file: ${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}"
	read -r -p "Press Enter to return to menu..." _
	clear

	case $status in
		0|1|255|130)
			return "$status"
			;;
		*)
			error_box "Installation Error" "The installer returned an unexpected status: $status"
			return "$status"
			;;
	esac
}

show_disk_menu() {
	local choice=""
	local status=0

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
	local choice=""
	local status=0

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
				run_install
				status=$?
				case $status in
					0)
						;;
					1|255|130)
						continue
						;;
					*)
						return "$status"
						;;
				esac
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
	local choice=""
	local status=0

	require_dialog || exit $?
	ensure_state_file || exit 1

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