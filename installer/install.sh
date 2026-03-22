#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=installer/ui.sh
source "$SCRIPT_DIR/ui.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh"
# shellcheck source=installer/disk.sh
source "$SCRIPT_DIR/disk.sh"
# shellcheck source=installer/modules/bootloader.sh
source "$SCRIPT_DIR/modules/bootloader.sh"
# shellcheck source=installer/modules/network.sh
source "$SCRIPT_DIR/modules/network.sh"
# shellcheck source=installer/modules/desktop.sh
source "$SCRIPT_DIR/modules/desktop.sh"
# shellcheck source=installer/executor.sh
source "$SCRIPT_DIR/executor.sh" || {
	printf 'failed to source %s/executor.sh\n' "$SCRIPT_DIR" >&2
	exit 1
}

INSTALL_USER_PASSWORD=${INSTALL_USER_PASSWORD:-""}
ZRAM=${ZRAM:-false}

ensure_executor_loaded() {
	if declare -F run_install >/dev/null 2>&1; then
		return 0
	fi

	printf 'run_install is not available after sourcing %s/executor.sh\n' "$SCRIPT_DIR" >&2
	return 1
}

state_or_default() {
	local key=${1:?state key is required}
	local default_value=${2-}
	local value=""

	value="$(get_state "$key" 2>/dev/null || true)"
	if [[ -n $value ]]; then
		printf '%s\n' "$value"
		return 0
	fi

	printf '%s\n' "$default_value"
}

apply_runtime_mode() {
	if flag_enabled "$DEV_MODE"; then
		INSTALL_UI_MODE=plain
	else
		INSTALL_UI_MODE=dialog
	fi

	set_state "DEV_MODE" "$DEV_MODE" || return 1
	set_state "INSTALL_UI_MODE" "$INSTALL_UI_MODE" || return 1
}

load_runtime_preferences() {
	DEV_MODE="$(state_or_default "DEV_MODE" "$DEV_MODE")"
	apply_runtime_mode
}

show_install_result_dialog() {
	local install_status=${1:-1}
	local disk=""
	local filesystem=""
	local boot_mode=""
	local desktop_profile=""
	local enable_zram=""
	local status_label="FAILED"
	local prompt=""
	local choice=""

	disk="$(state_or_default "DISK" "Not selected")"
	filesystem="$(state_or_default "FILESYSTEM" "ext4")"
	boot_mode="$(state_or_default "BOOT_MODE" "auto")"
	desktop_profile="$(desktop_profile_label "$(state_or_default "DESKTOP_PROFILE" "none")")"
	enable_zram="$(state_or_default "ENABLE_ZRAM" "false")"
	if [[ $install_status -eq 0 ]]; then
		status_label="SUCCESS"
	fi

	prompt="Disk: $disk\nFilesystem: $filesystem\nBoot mode: $boot_mode\nDesktop: $desktop_profile\nZRAM: $enable_zram\nStatus: $status_label\n\nThis will erase the selected disk during installation. Review the log if needed."

	choice="$(menu "Installation Complete" "$prompt" 18 72 4 \
		"reboot" "Reboot system" \
		"shutdown" "Shutdown system" \
		"back" "Return to main menu")"
	case $? in
		0)
			case "$choice" in
				reboot)
					reboot
					;;
				shutdown)
					poweroff
					;;
				back)
					return 0
					;;
			esac
			;;
		1|255)
			return 0
			;;
		*)
			return 0
			;;
	esac
}

install_progress_snapshot() {
	local tick=${1:-0}
	local excerpt=""
	local progress=5
	local label="Preparing installation..."

	excerpt="$(tail -n 50 "${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}" 2>/dev/null || true)"
	case "$excerpt" in
		*"Refreshing archlinux-keyring"*)
			progress=10
			label="Refreshing keyring..."
			;;
		*"Installing reflector on the live environment"*|*"Refreshing pacman mirrors"*|*"Refreshing pacman package databases"*)
			progress=15
			label="Preparing pacman and mirrors..."
			;;
		*"Creating a GPT partition table"*|*"Creating an MBR partition table"*|*"Creating the EFI system partition"*|*"Creating the root partition"*)
			progress=25
			label="Partitioning target disk..."
			;;
		*"Formatting the EFI partition as FAT32"*|*"Formatting the root partition"*)
			progress=35
			label="Formatting filesystems..."
			;;
		*"Mounting the root filesystem"*|*"Mounting the btrfs root subvolume"*|*"Mounting the EFI partition"*)
			progress=45
			label="Mounting target filesystem..."
			;;
		*"Installing the base Arch Linux packages"*)
			progress=$((55 + (tick % 20)))
			label="Installing packages..."
			;;
		*"Generating fstab"*)
			progress=82
			label="Generating fstab..."
			;;
		*"Configuring the target system inside chroot"*|*"Configuring the new system"*)
			progress=92
			label="Configuring installed system..."
			;;
		*"Installation completed successfully"*)
			progress=100
			label="Installation completed successfully."
			;;
	esac

	printf '%s|%s\n' "$progress" "$label"
}

run_install_with_dialog() {
	local install_pid=0
	local install_status=1
	local gauge_status=0
	local tick=0
	local progress_info=""
	local progress_value=0
	local progress_label=""

	: > "${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}" || return 1
	INSTALL_UI_MODE=plain run_install true >> "${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}" 2>&1 &
	install_pid=$!

	dialog --title "Install Log" --tailboxbg "${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}" 20 100
	{
		while kill -0 "$install_pid" 2>/dev/null; do
			progress_info="$(install_progress_snapshot "$tick")"
			progress_value=${progress_info%%|*}
			progress_label=${progress_info#*|}
			printf '%s\n' "$progress_value"
			printf '# %s\n' "$progress_label"
			tick=$((tick + 1))
			sleep 1
		done

		printf '100\n'
		printf '# Finishing installation...\n'
	} | dialog --title "ArchInstall Progress" --gauge "Installing system..." 10 70 0
	gauge_status=${PIPESTATUS[1]:-0}

	if [[ $gauge_status -ne 0 && -n $install_pid ]]; then
		kill -INT "$install_pid" 2>/dev/null || true
	fi

	wait "$install_pid"
	install_status=$?
	clear_screen
	return "$install_status"
}

select_filesystem() {
	local current_filesystem=${1:-ext4}
	local selected=""

	selected="$(menu "Filesystem" "Choose the root filesystem." 14 70 4 \
		"ext4" "Default fallback filesystem" \
		"btrfs" "Create @ and @home subvolumes with zstd compression")"
	case $? in
		0)
			printf '%s\n' "$selected"
			return 0
			;;
		1|255)
			return 1
			;;
		*)
			return 1
			;;
	esac
}

select_zram_preference() {
	local current_value=${1:-$ZRAM}
	local choice=""

	if flag_enabled "$current_value"; then
		current_value=true
	else
		current_value=false
	fi

	choice="$(menu "Zram" "Choose whether to enable zram swap." 12 50 2 \
		"yes" "Enable zram" \
		"no" "Disable zram")"
	case $? in
		0)
			case "$choice" in
				yes)
					printf 'true\n'
					return 0
					;;
				no)
					printf 'false\n'
					return 0
					;;
			esac
			printf 'false\n'
			return 0
			;;
		1|255)
			printf 'false\n'
			return 0
			;;
		*)
			printf 'false\n'
			return 0
			;;
	esac
}

prompt_required_input() {
	local title=${1:?title is required}
	local prompt=${2:?prompt is required}
	local initial_value=${3-}
	local value=""

	while true; do
		value="$(input_box "$title" "$prompt" "$initial_value" 12 76)"
		case $? in
			0)
				if [[ -n $value ]]; then
					printf '%s\n' "$value"
					return 0
				fi
				msg "$title" "A value is required."
				;;
			1|255)
				return 1
				;;
			*)
				return 1
				;;
		esac
		initial_value="$value"
	done
}

prompt_password() {
	local title=${1:?title is required}
	local first=""
	local second=""

	while true; do
		first="$(password_box "$title" "Enter the password." 12 76)"
		case $? in
			0)
				;;
			1|255)
				return 1
				;;
			*)
				return 1
				;;
		esac

		if [[ -z $first ]]; then
			msg "$title" "The password cannot be empty."
			continue
		fi

		second="$(password_box "$title" "Re-enter the password." 12 76)"
		case $? in
			0)
				;;
			1|255)
				return 1
				;;
			*)
				return 1
				;;
		esac

		if [[ $first != "$second" ]]; then
			msg "$title" "Passwords did not match."
			continue
		fi

		printf '%s\n' "$first"
		return 0
	done
}

configure_install_profile() {
	local hostname=""
	local timezone=""
	local locale=""
	local username=""
	local password=""
	local boot_mode=""
	local filesystem=""
	local enable_zram=""
	local desktop_profile=""
	local display_manager=""

	hostname="$(prompt_required_input "Hostname" "Set the system hostname." "$(state_or_default "HOSTNAME" "archlinux")")" || return 1
	timezone="$(prompt_required_input "Timezone" "Set the timezone, for example Europe/Berlin or UTC." "$(state_or_default "TIMEZONE" "UTC")")" || return 1
	locale="$(prompt_required_input "Locale" "Set the locale, for example en_US.UTF-8." "$(state_or_default "LOCALE" "en_US.UTF-8")")" || return 1
	username="$(prompt_required_input "Username" "Create the primary user account." "$(state_or_default "USERNAME" "archuser")")" || return 1
	filesystem="$(select_filesystem "$(state_or_default "FILESYSTEM" "ext4")")" || return 1
	enable_zram="$(select_zram_preference "$(state_or_default "ENABLE_ZRAM" "$ZRAM")")" || return 1
	desktop_profile="$(select_desktop_profile)" || return 1
	display_manager="$(select_display_manager "$desktop_profile")" || return 1
	password="$(prompt_password "User Password")" || return 1
	boot_mode="$(detect_boot_mode 2>/dev/null || printf 'uefi')"

	set_state "HOSTNAME" "$hostname" || return 1
	set_state "TIMEZONE" "$timezone" || return 1
	set_state "LOCALE" "$locale" || return 1
	set_state "USERNAME" "$username" || return 1
	set_state "FILESYSTEM" "$filesystem" || return 1
	set_state "ENABLE_ZRAM" "$enable_zram" || return 1
	set_state "DESKTOP_PROFILE" "$desktop_profile" || return 1
	set_state "DISPLAY_MANAGER" "$display_manager" || return 1
	set_state "BOOT_MODE" "$boot_mode" || return 1
	INSTALL_USER_PASSWORD="$password"

	msg "Profile Saved" "Installation profile updated.\n\nHostname: $hostname\nTimezone: $timezone\nLocale: $locale\nUser: $username\nFilesystem: $filesystem\nZram: $enable_zram\nDesktop: $(desktop_profile_label "$desktop_profile")\nDisplay manager: $(display_manager_label "$display_manager")\nBoot mode: $boot_mode"
}

validate_install_profile() {
	local missing=()

	has_state "HOSTNAME" || missing+=("hostname")
	has_state "TIMEZONE" || missing+=("timezone")
	has_state "LOCALE" || missing+=("locale")
	has_state "USERNAME" || missing+=("user")
	[[ -n $INSTALL_USER_PASSWORD ]] || missing+=("user password")

	if [[ ${#missing[@]} -eq 0 ]]; then
		return 0
	fi

	msg "Configuration Required" "Complete the installation profile before starting.\n\nMissing: ${missing[*]}"
	return 1
}

toggle_dev_mode() {
	if flag_enabled "$DEV_MODE"; then
		DEV_MODE=false
	else
		DEV_MODE=true
	fi

	apply_runtime_mode || return 1
	msg "Developer Mode" "DEV_MODE is now set to: $DEV_MODE\n\nInstall UI mode: $INSTALL_UI_MODE\n\nDEV_MODE=true shows live terminal logs. DEV_MODE=false uses the dialog progress gauge."
}

show_state_summary() {
	local disk
	local boot_mode
	local efi_partition
	local root_partition
	local hostname
	local timezone
	local locale
	local username
	local filesystem
	local enable_zram
	local desktop_profile
	local display_manager
	local password_state

	disk="$(get_state "DISK" 2>/dev/null || printf 'Not selected')"
	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || detect_boot_mode 2>/dev/null || printf 'Unknown')"
	efi_partition="$(get_state "EFI_PART" 2>/dev/null || printf 'Not created')"
	root_partition="$(get_state "ROOT_PART" 2>/dev/null || printf 'Not created')"
	hostname="$(state_or_default "HOSTNAME" "archlinux")"
	timezone="$(state_or_default "TIMEZONE" "UTC")"
	locale="$(state_or_default "LOCALE" "en_US.UTF-8")"
	username="$(state_or_default "USERNAME" "Not configured")"
	filesystem="$(state_or_default "FILESYSTEM" "ext4")"
	enable_zram="$(state_or_default "ENABLE_ZRAM" "false")"
	desktop_profile="$(state_or_default "DESKTOP_PROFILE" "none")"
	display_manager="$(state_or_default "DISPLAY_MANAGER" "none")"
	password_state="not set"
	[[ -n $INSTALL_USER_PASSWORD ]] && password_state="set"

	msg "Installer State" "Saved state:\n\nDisk: $disk\nBoot mode: $boot_mode\nEFI: $efi_partition\nRoot: $root_partition\nHostname: $hostname\nTimezone: $timezone\nLocale: $locale\nUser: $username\nFilesystem: $filesystem\nZram: $enable_zram\nDesktop: $(desktop_profile_label "$desktop_profile")\nDisplay manager: $(display_manager_label "$display_manager")\nUser password: $password_state\nDEV_MODE: $DEV_MODE\nUI mode: $INSTALL_UI_MODE" 22 76
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

	validate_install_profile || return 1

	message="This will prepare a bootable Arch Linux system on:\n\n$disk\n\nBoot mode: $(state_or_default "BOOT_MODE" "auto")\nHostname: $(state_or_default "HOSTNAME" "archlinux")\nTimezone: $(state_or_default "TIMEZONE" "UTC")\nLocale: $(state_or_default "LOCALE" "en_US.UTF-8")\nUser: $(state_or_default "USERNAME" "archuser")\nFilesystem: $(state_or_default "FILESYSTEM" "ext4")\nZram: $(state_or_default "ENABLE_ZRAM" "false")\nDesktop: $(desktop_profile_label "$(state_or_default "DESKTOP_PROFILE" "none")")\nDisplay manager: $(display_manager_label "$(state_or_default "DISPLAY_MANAGER" "none")")\n\nDestructive steps may erase existing data."
	if flag_enabled "$DEV_MODE"; then
		message+="\n\nDev mode flags:\nSKIP_PARTITION=$SKIP_PARTITION\nSKIP_PACSTRAP=$SKIP_PACSTRAP\nSKIP_CHROOT=$SKIP_CHROOT\nINSTALL_UI_MODE=$INSTALL_UI_MODE"
	fi

	confirm "Confirm Installation" "$message\n\nContinue?" 18 76
}

run_install_flow() {
	local status=0
	local prompt_status=0

	confirm_installation
	prompt_status=$?
	if [[ $prompt_status -ne 0 ]]; then
		return "$prompt_status"
	fi

	apply_runtime_mode || return 1
	if install_ui_uses_dialog; then
		step_box "Starting Installer" "Launching unattended install core. Real-time logs will stay visible in the dialog log view."
		run_install_with_dialog
		status=$?
	else
		run_install true
		status=$?
	fi

	show_install_result_dialog "$status" || true

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
			"config" "Configure hostname, timezone, locale, and user" \
			"dev" "Toggle developer mode (current: $DEV_MODE / $INSTALL_UI_MODE)" \
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
				run_install_flow
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
				config)
					configure_install_profile || true
					;;
				dev)
					toggle_dev_mode || true
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
	ensure_executor_loaded || exit 1
	ensure_state_file || exit 1
	load_runtime_preferences || exit 1

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