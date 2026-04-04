#!/usr/bin/env bash
# TEST_OK

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

safe_source_module() {
	local module_path=${1:?module path is required}

	if [[ ! -r $module_path ]]; then
		printf '[WARN] Optional module missing: %s\n' "$module_path" >&2
		return 1
	fi

	# shellcheck disable=SC1090
	if [[ ${UI_MODE:-dialog} == "dialog" && ${DEV_MODE:-false} != "true" ]]; then
		if source "$module_path" >/dev/null 2>&1; then
			return 0
		fi
	elif source "$module_path"; then
		return 0
	fi

	printf '[WARN] Failed to load optional module: %s\n' "$module_path" >&2
	return 1
}

# shellcheck source=installer/ui.sh
source "$SCRIPT_DIR/ui.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh"
# shellcheck source=installer/core/hooks.sh
safe_source_module "$SCRIPT_DIR/core/hooks.sh" || true
# shellcheck source=installer/core/module-registry.sh
safe_source_module "$SCRIPT_DIR/core/module-registry.sh" || true
# shellcheck source=installer/core/plugin-loader.sh
safe_source_module "$SCRIPT_DIR/core/plugin-loader.sh" || true
# shellcheck source=installer/modules/config.sh
safe_source_module "$SCRIPT_DIR/modules/config.sh" || true
# shellcheck source=installer/modules/runtime.sh
safe_source_module "$SCRIPT_DIR/modules/runtime.sh" || true
# shellcheck source=installer/modules/hardware.sh
safe_source_module "$SCRIPT_DIR/modules/hardware.sh" || true
# shellcheck source=installer/modules/environment.sh
safe_source_module "$SCRIPT_DIR/modules/environment.sh" || true
# shellcheck source=installer/executor.sh
safe_source_module "$SCRIPT_DIR/executor.sh" || {
	printf 'failed to source %s/executor.sh\n' "$SCRIPT_DIR" >&2
	exit 1
}
# shellcheck source=installer/disk.sh
safe_source_module "$SCRIPT_DIR/disk.sh" || true
# shellcheck source=installer/modules/network.sh
safe_source_module "$SCRIPT_DIR/modules/network.sh" || true
# shellcheck source=installer/modules/desktop.sh
safe_source_module "$SCRIPT_DIR/modules/desktop.sh" || true
# shellcheck source=installer/modules/secureboot.sh
safe_source_module "$SCRIPT_DIR/modules/secureboot.sh" || true
# shellcheck source=installer/modules/profiles.sh
safe_source_module "$SCRIPT_DIR/modules/profiles.sh" || true
# shellcheck source=installer/modules/profile.sh
safe_source_module "$SCRIPT_DIR/modules/profile.sh" || true
# shellcheck source=installer/modules/packages.sh
safe_source_module "$SCRIPT_DIR/modules/packages.sh" || true
# shellcheck source=installer/modules/luks.sh
safe_source_module "$SCRIPT_DIR/modules/luks.sh" || true
# shellcheck source=installer/modules/snapshots.sh
safe_source_module "$SCRIPT_DIR/modules/snapshots.sh" || true

INSTALL_USER_PASSWORD=${INSTALL_USER_PASSWORD:-""}
INSTALL_ROOT_PASSWORD=${INSTALL_ROOT_PASSWORD:-""}
INSTALL_SAFE_MODE=${INSTALL_SAFE_MODE:-true}
ZRAM=${ZRAM:-false}
LIVE_CONSOLE_FONT=${LIVE_CONSOLE_FONT:-ter-v16n}
ARCHINSTALL_DEBUG_LOG=${ARCHINSTALL_DEBUG_LOG:-/tmp/archinstall_debug.log}
ARCHINSTALL_PROGRESS_DIALOG_PID=${ARCHINSTALL_PROGRESS_DIALOG_PID:-0}
ARCHINSTALL_PROGRESS_KEEPALIVE_FD=${ARCHINSTALL_PROGRESS_KEEPALIVE_FD:-}
ARCHINSTALL_PROGRESS_WRITER_FD=${ARCHINSTALL_PROGRESS_WRITER_FD:-}
ARCHINSTALL_BOOT_SUMMARY=${ARCHINSTALL_BOOT_SUMMARY:-}
ARCHINSTALL_ENV_SUMMARY=${ARCHINSTALL_ENV_SUMMARY:-}
ARCHINSTALL_GPU_LABEL_CACHED=${ARCHINSTALL_GPU_LABEL_CACHED:-}
ARCHINSTALL_NETWORK_STATUS=${ARCHINSTALL_NETWORK_STATUS:-}

log_debug() {
	local message=${1:-}

	printf '[%s] %s\n' "$(date '+%F %T')" "$message" >> "$ARCHINSTALL_DEBUG_LOG" 2>/dev/null || true
}

if type refresh_runtime_system_state >/dev/null 2>&1 && type runtime_boot_summary >/dev/null 2>&1 && type runtime_environment_summary >/dev/null 2>&1; then
	log_debug "Runtime module loaded successfully"
else
	log_debug "Runtime module compatibility mode enabled"
fi

if type load_installer_plugins >/dev/null 2>&1; then
	load_installer_plugins || true
fi
if type archinstall_register_builtin_modules >/dev/null 2>&1; then
	archinstall_register_builtin_modules || true
fi
if type sync_install_config_json >/dev/null 2>&1; then
	sync_install_config_json >/dev/null 2>&1 || true
fi

log_info() {
	local message=${1:-}

	printf '[%s] %s\n' "$(date '+%F %T')" "$message" >> "${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}" 2>/dev/null || true
	printf '[%s] %s\n' "$(date '+%F %T')" "$message" >> "$ARCHINSTALL_DEBUG_LOG" 2>/dev/null || true
}

safe_runtime_boot_summary() {
	if type runtime_boot_summary >/dev/null 2>&1; then
		runtime_boot_summary 2>/dev/null || printf 'BIOS (Secure Boot: Not Supported)\n'
		return 0
	fi

	printf 'BIOS (Secure Boot: Not Supported)\n'
}

safe_runtime_environment_summary() {
	if type runtime_environment_summary >/dev/null 2>&1; then
		runtime_environment_summary 2>/dev/null || printf 'Unknown\n'
		return 0
	fi

	printf 'Unknown\n'
}

sync_install_ui_mode() {
	if [[ ${UI_MODE:-dialog} == "tty" ]] || flag_enabled "$DEV_MODE"; then
		INSTALL_UI_MODE=plain
	else
		INSTALL_UI_MODE=dialog
	fi
}

estimate_install_step_count() {
	local boot_mode=${1:-uefi}
	local desktop_profile=${2:-none}
	local total_steps=14

	if [[ $boot_mode == "uefi" ]]; then
		total_steps=$((total_steps + 1))
	fi
	if [[ $desktop_profile == "kde" ]]; then
		total_steps=$((total_steps + 2))
	fi

	printf '%s\n' "$total_steps"
}

last_install_log_excerpt() {
	local log_file=${1:?log file is required}

	if [[ ! -f $log_file ]]; then
		printf 'Waiting for installer log output...\n'
		return 0
	fi

	tail -n 6 "$log_file" 2>/dev/null | sed 's/"/'"'"'/g' | tr -cd '\11\12\15\40-\176'
}

progress_log_excerpt() {
	local log_file=${1:?log file is required}

	if [[ ! -f $log_file ]]; then
		printf 'Waiting for installer log output...\n'
		return 0
	fi

	tail -n 12 "$log_file" 2>/dev/null | grep -v '\[DEBUG\]' | tail -n 8 | sed "s/\"/'/g" | tr -cd '\11\12\15\40-\176'
}

install_progress_percent() {
	local log_file=${1:?log file is required}
	local _unused=${2:-}
	local percent=0
	local last_stage_line=""

	if [[ -f $log_file ]]; then
		last_stage_line="$(grep -o '\[STAGE:[0-9]*\]' "$log_file" 2>/dev/null | tail -n1 || true)"
		if [[ $last_stage_line =~ \[STAGE:([0-9]+)\] ]]; then
			percent="${BASH_REMATCH[1]}"
		fi
	fi

	if (( percent > 95 )); then
		percent=95
	fi

	printf '%s\n' "$percent"
}

install_current_stage_label() {
	local log_file=${1:?log file is required}
	local last_stage=""

	if [[ -f $log_file ]]; then
		last_stage="$(grep -oE '\[STAGE:[0-9]+\] .+' "$log_file" 2>/dev/null | tail -n1 | sed 's/^\[STAGE:[0-9]*\] //' || true)"
	fi

	printf '%s\n' "${last_stage:-Preparing installer}"
}

render_install_progress_text() {
	local progress_log=${1:?progress log is required}
	local percent=${2:?percent is required}
	local current_step=${3:-Preparing install}
	local boot_mode=${4:-auto}
	local filesystem=${5:-ext4}
	local desktop_profile=${6:-none}
	local display_mode=${7:-auto}
	local secure_boot_state="$(state_or_default "CURRENT_SECURE_BOOT_STATE" "unsupported")"
	local environment_label_value="${ARCHINSTALL_ENV_SUMMARY:-$(safe_runtime_environment_summary)}"
	local excerpt=""

	excerpt="$(progress_log_excerpt "$progress_log")"
	printf 'Installing system... %s%%\n\nCurrent step: %s\nBoot mode: %s\nEnvironment: %s\nFilesystem: %s\nDesktop: %s\nDisplay mode: %s\n\nLatest logs:\n%s\n' \
		"$percent" \
		"$(sanitize_dialog_text "$current_step")" \
		"$(sanitize_dialog_text "$(boot_mode_status_label "$boot_mode" "$secure_boot_state")")" \
		"$(sanitize_dialog_text "$environment_label_value")" \
		"$(sanitize_dialog_text "$filesystem")" \
		"$(sanitize_dialog_text "$(desktop_profile_label "$desktop_profile")")" \
		"$(sanitize_dialog_text "$(display_mode_label "$display_mode")")" \
		"$excerpt"
}

start_install_progress_dialog() {
	local progress_fifo=${1:?progress fifo is required}
	local progress_error_log=${2:?progress error log is required}

	log_debug "progress relay starting for fifo=$progress_fifo"
	bash -c '
		set +e
		fifo=$1
		error_log=$2
		backtitle=$3
		while IFS= read -r line; do
			printf "%s\n" "$line"
		done < "$fifo" | dialog \
			--clear \
			--backtitle "$backtitle" \
			--title "Installing Arch Linux" \
			--gauge "Preparing installer..." \
			22 100 0 \
			2> "$error_log"
	' _ "$progress_fifo" "$progress_error_log" "$ARCHINSTALL_BACKTITLE" &
	ARCHINSTALL_PROGRESS_DIALOG_PID=$!
	log_debug "progress dialog started pid=$ARCHINSTALL_PROGRESS_DIALOG_PID"
	return 0
}

open_install_progress_writer() {
	local progress_fifo=${1:?progress fifo is required}

	log_debug "opening progress keepalive for fifo=$progress_fifo"
	exec {ARCHINSTALL_PROGRESS_KEEPALIVE_FD}<>"$progress_fifo" || return 1
	log_debug "opening progress writer for fifo=$progress_fifo"
	exec {ARCHINSTALL_PROGRESS_WRITER_FD}>"$progress_fifo" || return 1
	log_debug "progress writer started fd=$ARCHINSTALL_PROGRESS_WRITER_FD"
	return 0
}

close_install_progress_writer() {
	if [[ -n ${ARCHINSTALL_PROGRESS_WRITER_FD:-} ]]; then
		exec {ARCHINSTALL_PROGRESS_WRITER_FD}>&-
		ARCHINSTALL_PROGRESS_WRITER_FD=
	fi
	if [[ -n ${ARCHINSTALL_PROGRESS_KEEPALIVE_FD:-} ]]; then
		exec {ARCHINSTALL_PROGRESS_KEEPALIVE_FD}>&-
		ARCHINSTALL_PROGRESS_KEEPALIVE_FD=
	fi
}

write_install_progress_dialog() {
	local progress_fifo=${1:?progress fifo is required}
	local percent=${2:?percent is required}
	local current_step=${3:-Preparing install}
	local boot_mode=${4:-auto}
	local filesystem=${5:-ext4}
	local desktop_profile=${6:-none}
	local display_mode=${7:-auto}
	local progress_log=${8:?progress log is required}
	local message=""

	if [[ -z ${ARCHINSTALL_PROGRESS_WRITER_FD:-} ]]; then
		return 1
	fi

	message="$(render_install_progress_text "$progress_log" "$percent" "$current_step" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode")"
	{
		printf 'XXX\n'
		printf '%s\n' "$percent"
		printf '%s\n' "$message"
		printf 'XXX\n'
	} >&${ARCHINSTALL_PROGRESS_WRITER_FD}
}

finalize_install_progress_dialog() {
	local progress_fifo=${1:?progress fifo is required}
	local progress_log=${2:?progress log is required}
	local boot_mode=${3:-auto}
	local filesystem=${4:-ext4}
	local desktop_profile=${5:-none}
	local display_mode=${6:-auto}

	if [[ -n ${ARCHINSTALL_PROGRESS_WRITER_FD:-} ]]; then
		write_install_progress_dialog "$progress_fifo" 100 "Installation complete" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode" "$progress_log" || true
		sleep 1
	fi
}

show_install_progress_tty() {
	local log_file=${1:?log file is required}
	local percent=${2:?percent is required}
	local current_step=${3:-Preparing install}
	local boot_mode=${4:-auto}
	local filesystem=${5:-ext4}
	local desktop_profile=${6:-none}
	local display_mode=${7:-auto}
	local progress_key=""
	local excerpt=""
	local secure_boot_state="$(state_or_default "CURRENT_SECURE_BOOT_STATE" "unsupported")"
	local environment_label_value="$(safe_runtime_environment_summary)"

	progress_key="${percent}:${current_step}:${display_mode}"
	if [[ ${ARCHINSTALL_LAST_TTY_PROGRESS_KEY:-} == "$progress_key" ]]; then
		return 0
	fi

	ARCHINSTALL_LAST_TTY_PROGRESS_KEY=$progress_key
	excerpt="$(progress_log_excerpt "$log_file")"
	clear_screen
	printf 'Installing Arch Linux\n\n'
	printf 'Progress: %s%%\n' "$percent"
	printf 'Current step: %s\n' "$current_step"
	printf 'Boot mode: %s\n' "$(boot_mode_status_label "$boot_mode" "$secure_boot_state")"
	printf 'Environment: %s\n' "$environment_label_value"
	printf 'Filesystem: %s\n' "$filesystem"
	printf 'Desktop: %s\n' "$(desktop_profile_label "$desktop_profile")"
	printf 'Display mode: %s\n\n' "$(display_mode_label "$display_mode")"
	printf 'Latest logs:\n%s\n' "$excerpt"
}

show_install_failure_dialog() {
	local log_file=${1:?log file is required}
	local excerpt=""

	excerpt="$(tail -n 50 "$log_file" 2>/dev/null | sed 's/"/'"'"'/g' | tr -cd '\11\12\15\40-\176' || true)"
	if [[ -z $excerpt ]]; then
		excerpt='No log output captured.'
	fi

	error_box "Installation Failed" "The installer reported a failure.\n\nLatest log lines:\n$excerpt\n\nFull log: $log_file"
}

apply_live_console_keymap() {
	local keymap=${1:-us}

	if command -v loadkeys >/dev/null 2>&1; then
		loadkeys "$keymap" >/dev/null 2>&1 || true
	fi

	set_state "KEYMAP" "$keymap" >/dev/null 2>&1 || true
}

apply_live_console_font() {
	if command -v setfont >/dev/null 2>&1; then
		setfont "$LIVE_CONSOLE_FONT" >/dev/null 2>&1 || true
	fi
}

select_startup_keymap() {
	local current_keymap=${1:-us}
	local choice=""
	local custom_keymap=""

	menu "Console Keyboard" "Choose the keyboard layout for the live ISO console.\n\nThis only affects the console during installation.\n\nCurrent: $current_keymap" 18 76 6 \
		"us"     "US English (ANSI QWERTY)" \
		"uk"     "UK English (ISO QWERTY with £)" \
		"de"     "German (ISO QWERTZ)" \
		"fr"     "French (AZERTY)" \
		"trq"    "Turkish Q (ISO Q layout)" \
		"custom" "Enter a custom keymap code (loadkeys compatible)"
	choice="$DIALOG_RESULT"
	case $DIALOG_STATUS in
		0)
			if [[ $choice == "custom" ]]; then
				input_box "Console Keyboard" "Enter a live ISO keymap such as us, trq, or de." "$current_keymap" 12 70
				custom_keymap="$DIALOG_RESULT"
				case $DIALOG_STATUS in
					0)
						[[ -n $custom_keymap ]] || return 1
						printf '%s\n' "$custom_keymap"
						return 0
						;;
					*)
						return 1
						;;
				esac
			fi

			printf '%s\n' "$choice"
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

prepare_live_console() {
	local selected_keymap=""
	local current_keymap=""

	apply_live_console_keymap "us"
	apply_live_console_font

	current_keymap="$(state_or_default "KEYMAP" "us")"
	selected_keymap="$(select_startup_keymap "$current_keymap")" || {
		apply_live_console_keymap "$current_keymap"
		return 0
	}

	apply_live_console_keymap "$selected_keymap"
}

warn_if_low_live_iso_space() {
	local usage_summary=""
	local available_kb=0
	local threshold_kb=1048576

	usage_summary="$(df -h / 2>/dev/null | awk 'NR==2 {printf "Total: %s\nUsed: %s\nFree: %s\nUsage: %s\n", $2, $3, $4, $5}' || true)"
	available_kb="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}' || printf '0')"

	if [[ ${available_kb:-0} =~ ^[0-9]+$ ]] && (( available_kb < threshold_kb )); then
		warning_box "Low ISO Space" "The live ISO root filesystem appears low on available space.\n\n${usage_summary:-Usage details unavailable.}\n\nThe Arch ISO runs from RAM. Installing large packages here exhausts memory and can destabilize the session. Keep heavy installs inside pacstrap - they go to the target disk, not RAM."
	fi
}

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

refresh_runtime_context() {
	if type refresh_runtime_system_state >/dev/null 2>&1; then
		refresh_runtime_system_state >/dev/null 2>&1 || log_debug "Runtime detection failed: refresh_runtime_system_state"
	else
		log_debug "Runtime detection unavailable: refresh_runtime_system_state"
	fi
	if type refresh_hardware_state >/dev/null 2>&1; then
		refresh_hardware_state >/dev/null 2>&1 || log_debug "Runtime detection failed: refresh_hardware_state"
	else
		log_debug "Runtime detection unavailable: refresh_hardware_state"
	fi
	ARCHINSTALL_BOOT_SUMMARY="$(safe_runtime_boot_summary 2>/dev/null | tr -d '\n' || printf 'Unknown')"
	ARCHINSTALL_ENV_SUMMARY="$(safe_runtime_environment_summary 2>/dev/null | tr -d '\n' || printf 'Unknown')"
	ARCHINSTALL_GPU_LABEL_CACHED="$(state_or_default "GPU_LABEL" "Generic")"
	ARCHINSTALL_NETWORK_STATUS="$(type detect_network_status >/dev/null 2>&1 && detect_network_status 2>/dev/null || printf 'Unknown')"
	ARCHINSTALL_BACKTITLE="ArchInstall Framework | $ARCHINSTALL_BOOT_SUMMARY | $ARCHINSTALL_ENV_SUMMARY | Net: $ARCHINSTALL_NETWORK_STATUS"
	return 0
}

check_network_before_install() {
	if [[ ${ARCHINSTALL_NETWORK_STATUS:-} == "Not Connected" ]]; then
		warning_box "No Network Connection" \
			"No active network connection detected.\n\nThe installer requires internet access to run pacstrap.\n\nStatus: $ARCHINSTALL_NETWORK_STATUS\n\nConnect via iwctl, dhcpcd, or NetworkManager before continuing."
	fi
}

installer_context_header() {
	printf 'Boot Mode: %s\nEnvironment: %s\nGPU: %s\nNetwork: %s' \
		"${ARCHINSTALL_BOOT_SUMMARY:-$(safe_runtime_boot_summary)}" \
		"${ARCHINSTALL_ENV_SUMMARY:-$(safe_runtime_environment_summary)}" \
		"${ARCHINSTALL_GPU_LABEL_CACHED:-$(state_or_default "GPU_LABEL" "Generic")}" \
		"${ARCHINSTALL_NETWORK_STATUS:-Unknown}"
}

select_boolean_value() {
	local title=${1:?title is required}
	local prompt=${2:?prompt is required}
	local current_value=${3:-false}
	local enable_label=${4:-Enable}
	local disable_label=${5:-Disable}

	menu "$title" "$prompt\n\nCurrent: $current_value" 14 70 3 \
		"true" "$enable_label" \
		"false" "$disable_label"

	case $DIALOG_STATUS in
		0)
			printf '%s\n' "$DIALOG_RESULT"
			return 0
			;;
		*)
			return 1
			;;
	esac
}

select_snapshot_provider() {
	local filesystem=${1:-ext4}
	local install_profile=${2:-daily}
	local current_provider=${3:-}

	if [[ -z $current_provider ]] && declare -F snapshot_default_provider >/dev/null 2>&1; then
		current_provider="$(snapshot_default_provider "$filesystem" "$install_profile")"
	fi
	current_provider=${current_provider:-none}

	menu "Snapshots" "Choose an optional snapshot engine.\n\nCurrent: $(snapshot_provider_label "$current_provider")\nFilesystem: $filesystem" 16 72 4 \
		"none" "No snapshot integration" \
		"snapper" "Btrfs snapshots with timeline cleanup" \
		"timeshift" "Timeshift snapshots"

	case $DIALOG_STATUS in
		0)
			printf '%s\n' "$DIALOG_RESULT"
			return 0
			;;
		*)
			return 1
			;;
	esac
}

require_yes_confirmation() {
	local title=${1:-"Final Confirmation"}
	local prompt=${2:-"Type YES to continue."}

	input_box "$title" "$prompt" "" 12 76
	if [[ $DIALOG_STATUS -ne 0 ]]; then
		return 1
	fi

	[[ ${DIALOG_RESULT:-} == "YES" ]]
}

join_csv_values() {
	local joined=""
	local item=""

	for item in "$@"; do
		[[ -n $item ]] || continue
		if [[ -z $joined ]]; then
			joined=$item
		else
			joined+=",$item"
		fi
	done

	printf '%s\n' "$joined"
}

apply_runtime_mode() {
	sync_install_ui_mode

	set_state "DEV_MODE" "$DEV_MODE" || return 1
	set_state "INSTALL_SAFE_MODE" "$INSTALL_SAFE_MODE" || return 1
	set_state "UI_MODE" "${UI_MODE:-dialog}" || return 1
	set_state "INSTALL_UI_MODE" "$INSTALL_UI_MODE" || return 1
}

load_runtime_preferences() {
	DEV_MODE="$(state_or_default "DEV_MODE" "$DEV_MODE")"
	if [[ ${UI_MODE:-dialog} != "tty" ]]; then
		UI_MODE="$(state_or_default "UI_MODE" "${UI_MODE:-dialog}")"
	fi
	debug_ui_mode
	refresh_runtime_context || true
	apply_runtime_mode
}

post_install_kernel_label() {
	case "$(state_or_default "KERNEL_PACKAGE" "linux")" in
		linux)
			printf 'Linux\n'
			;;
		*)
			printf '%s\n' "$(state_or_default "KERNEL_PACKAGE" "linux")"
			;;
	esac
}

post_install_bootloader_label() {
	local boot_mode="$(state_or_default "BOOT_MODE" "auto")"

	case "$boot_mode" in
		uefi)
			printf 'systemd-boot\n'
			;;
		*)
			printf 'GRUB\n'
			;;
	esac
}

post_install_filesystem_label() {
	case "$(state_or_default "FILESYSTEM" "ext4")" in
		btrfs)
			printf 'Btrfs\n'
			;;
		ext4)
			printf 'Ext4\n'
			;;
		*)
			printf '%s\n' "$(state_or_default "FILESYSTEM" "ext4")"
			;;
	esac
}

post_install_disk_type_label() {
	disk_type_label "$(state_or_default "DISK_TYPE" "unknown")"
}

install_summary_text() {
	local install_status=${1:-1}
	local disk="$(state_or_default "DISK" "Not selected")"
	local disk_type="$(post_install_disk_type_label)"
	local disk_display="$disk"
	local filesystem="$(post_install_filesystem_label)"
	local boot_mode="$(state_or_default "BOOT_MODE" "auto")"
	local kernel="$(post_install_kernel_label)"
	local desktop_profile="$(desktop_profile_label "$(state_or_default "DESKTOP_PROFILE" "none")")"
	local install_profile="$(install_profile_label "$(state_or_default "INSTALL_PROFILE" "daily")")"
	local display_manager="$(display_manager_label "$(state_or_default "DISPLAY_MANAGER" "none")")"
	local bootloader="$(post_install_bootloader_label)"
	local boot_label="BIOS"

	if [[ $boot_mode == "uefi" ]]; then
		boot_label="UEFI"
	fi

	if [[ -n $disk_type ]]; then
		disk_display="$disk ($disk_type)"
	fi

	if [[ $install_status -ne 0 ]]; then
		printf 'Installation failed.\n'
		return 0
	fi

	printf 'Disk       : %s\nFilesystem : %s\nBoot Mode  : %s\nKernel     : %s\nProfile    : %s\nDesktop    : %s\nDisplay    : %s\nBootloader : %s\n\n----------------------------\n\nSelect action:' \
		"$disk_display" \
		"$filesystem" \
		"$boot_label" \
		"$kernel" \
		"$install_profile" \
		"$desktop_profile" \
		"$display_manager" \
		"$bootloader"
}

show_post_install_screen() {
	local install_status=${1:-1}
	local summary_text=""
	local dialog_enabled=false
	local choice=""
	local dialog_status=0

	if [[ $install_status -ne 0 ]]; then
		return 0
	fi

	summary_text="$(install_summary_text "$install_status")"
	if [[ ${UI_MODE:-dialog} != "tty" ]] && require_dialog >/dev/null 2>&1; then
		dialog_enabled=true
	fi

	log_debug "[DEBUG] Showing post-install screen"
	if [[ $dialog_enabled == true ]]; then
		log_debug "[DEBUG] Dialog mode: yes"
	else
		log_debug "[DEBUG] Dialog mode: no"
	fi

	if [[ $dialog_enabled == true ]]; then
		while true; do
			safe_dialog \
				--clear \
				--backtitle "$ARCHINSTALL_BACKTITLE" \
				--title "$(sanitize_dialog_text "Installation Complete")" \
				--no-ok \
				--no-cancel \
				--menu "$(sanitize_dialog_text "$summary_text")" \
				22 72 3 \
				"1" "Reboot system" \
				"2" "Shutdown system" \
				"3" "Return to Menu" \
				3>&1 1>&2 2>&3
			choice="$DIALOG_RESULT"
			dialog_status=$DIALOG_STATUS
			case $dialog_status in
				0)
					log_debug "[DEBUG] User selected: $choice"
					case "$choice" in
						1)
							reboot
							return 0
							;;
						2)
							poweroff
							return 0
							;;
						3)
							return 0
							;;
					esac
					;;
				1|255)
					log_debug "[DEBUG] User selected: 3"
					return 0
					;;
				*)
					if [[ ${ARCHINSTALL_LAST_UI_FAILURE:-false} == true ]]; then
						break
					fi
					;;
			esac
		done
	fi

	while true; do
		printf '\nInstallation Complete\n\n%s\n\n' "$summary_text" >/dev/tty
		printf '1) Reboot system\n2) Shutdown system\n3) Return to menu\n\nSelect an action [1-3]: ' >/dev/tty
		if ! IFS= read -r choice </dev/tty; then
			log_debug "[DEBUG] User selected: 3"
			return 0
		fi

		case "$choice" in
			1)
				log_debug "[DEBUG] User selected: 1"
				reboot
				return 0
				;;
			2)
				log_debug "[DEBUG] User selected: 2"
				poweroff
				return 0
				;;
			3)
				log_debug "[DEBUG] User selected: 3"
				return 0
				;;
			*)
				printf 'Invalid selection. Enter 1, 2, or 3.\n' >/dev/tty
				;;
		esac
	done
}

show_install_result_dialog() {
	show_post_install_screen "$@"
}

run_install_with_dialog() {
	local install_pid=0
	local install_status=1
	local log_file="${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}"
	local progress_log="/tmp/archinstall_progress.log"
	local progress_fifo=""
	local progress_error_log=""
	local progress_dialog_pid=0
	local expected_steps=0
	local percent=0
	local current_step="Preparing install"
	local boot_mode=""
	local filesystem=""
	local desktop_profile=""
	local display_mode=""
	local MAX_RETRY=3
	local RETRY_COUNT=0
	local tty_fallback_active=false

	stop_progress_dialog() {
		close_install_progress_writer
		if (( progress_dialog_pid > 0 )); then
			kill "$progress_dialog_pid" >/dev/null 2>&1 || true
			sleep 1
			kill -9 "$progress_dialog_pid" >/dev/null 2>&1 || true
			wait "$progress_dialog_pid" 2>/dev/null || true
			progress_dialog_pid=0
		fi
	}

	cleanup_progress_dialog() {
		stop_progress_dialog
		[[ -n $progress_fifo ]] && rm -f "$progress_fifo" 2>/dev/null || true
		[[ -n $progress_error_log ]] && rm -f "$progress_error_log" 2>/dev/null || true
	}

	: > "$log_file" || return 1
	: > "$progress_log" || return 1
	: > "$ARCHINSTALL_DEBUG_LOG" || true
	log_debug "run_install_with_dialog entered"
	boot_mode="$(state_or_default "BOOT_MODE" "auto")"
	filesystem="$(state_or_default "FILESYSTEM" "ext4")"
	desktop_profile="$(state_or_default "DESKTOP_PROFILE" "none")"
	display_mode="$(state_or_default "DISPLAY_MODE" "auto")"
	expected_steps="$(estimate_install_step_count "$boot_mode" "$desktop_profile")"
	progress_fifo="$(mktemp -u /tmp/archinstall_progress_fifo.XXXXXX)"
	progress_error_log="$(mktemp /tmp/archinstall_progress_error.XXXXXX 2>/dev/null || printf '/tmp/archinstall_progress_error.log')"
	log_debug "progress fifo path prepared: $progress_fifo"
	if ! mkfifo "$progress_fifo"; then
		log_debug "progress fifo creation failed"
		log_ui_error "[UI ERROR] could not create progress fifo; switching to TTY progress"
		set_ui_mode tty
		tty_fallback_active=true
	fi
	if [[ $tty_fallback_active == false && ${UI_MODE:-dialog} != "tty" ]]; then
		if open_install_progress_writer "$progress_fifo" && start_install_progress_dialog "$progress_fifo" "$progress_error_log"; then
			progress_dialog_pid=$ARCHINSTALL_PROGRESS_DIALOG_PID
			log_debug "progress system started writer_fd=$ARCHINSTALL_PROGRESS_WRITER_FD dialog_pid=$progress_dialog_pid"
			write_install_progress_dialog "$progress_fifo" 0 "Starting installer" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode" "$progress_log" || true
		else
			log_debug "progress system startup failed; falling back to tty"
			set_ui_mode tty
			tty_fallback_active=true
			apply_runtime_mode || true
		fi
	fi
	log_debug "run_install launch requested"
	check_network_before_install || true
	apply_runtime_mode || true
	INSTALL_UI_MODE="$INSTALL_UI_MODE" ARCHINSTALL_PROGRESS_LOG="$progress_log" run_install >> "$log_file" 2>&1 &
	install_pid=$!
	log_debug "run_install started pid=$install_pid"

	while kill -0 "$install_pid" 2>/dev/null; do
		sync_install_ui_mode
		percent="$(install_progress_percent "$log_file" "$expected_steps")"
		current_step="$(install_current_stage_label "$log_file")"
		if [[ $tty_fallback_active == true || ${UI_MODE:-dialog} == "tty" ]]; then
			log_debug "progress switching to tty mode"
			stop_progress_dialog
			show_install_progress_tty "$log_file" "$percent" "$current_step" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode"
		else
			if (( progress_dialog_pid <= 0 )) || ! kill -0 "$progress_dialog_pid" 2>/dev/null; then
				RETRY_COUNT=$((RETRY_COUNT + 1))
				log_debug "progress dialog not alive retry=$RETRY_COUNT"
				if [[ -s $progress_error_log ]]; then
					log_ui_error "[UI ERROR] progress dialog exited: $(tr -cd '\11\12\15\40-\176' < "$progress_error_log")"
				fi
				if (( RETRY_COUNT >= MAX_RETRY )); then
					log_debug "progress dialog retry limit reached; switching to tty"
					set_ui_mode tty
					tty_fallback_active=true
					apply_runtime_mode || true
					show_install_progress_tty "$log_file" "$percent" "$current_step" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode"
					continue
				fi
				stop_progress_dialog
				if open_install_progress_writer "$progress_fifo" && start_install_progress_dialog "$progress_fifo" "$progress_error_log"; then
					progress_dialog_pid=$ARCHINSTALL_PROGRESS_DIALOG_PID
					log_debug "progress dialog restarted pid=$progress_dialog_pid"
				else
					log_debug "progress dialog restart failed; switching to tty"
					set_ui_mode tty
					tty_fallback_active=true
					apply_runtime_mode || true
					show_install_progress_tty "$log_file" "$percent" "$current_step" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode"
					continue
				fi
			fi

			if write_install_progress_dialog "$progress_fifo" "$percent" "$current_step" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode" "$progress_log"; then
				RETRY_COUNT=0
			else
				RETRY_COUNT=$((RETRY_COUNT + 1))
				log_debug "progress writer failed retry=$RETRY_COUNT"
				if (( RETRY_COUNT >= MAX_RETRY )); then
					log_ui_error "[UI ERROR] install progress dialog failed repeatedly; switching to TTY progress"
					log_debug "progress writer retry limit reached; switching to tty"
					set_ui_mode tty
					tty_fallback_active=true
					apply_runtime_mode || true
					show_install_progress_tty "$log_file" "$percent" "$current_step" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode"
				fi
			fi
		fi
		sleep 1
	done

	log_debug "run_install process exited"
	if [[ ${UI_MODE:-dialog} == "dialog" && $tty_fallback_active == false ]]; then
		finalize_install_progress_dialog "$progress_fifo" "$progress_log" "$boot_mode" "$filesystem" "$desktop_profile" "$display_mode"
	fi
	cleanup_progress_dialog
	wait "$install_pid"
	install_status=$?
	log_debug "run_install exit status=$install_status"
	clear_screen
	return "$install_status"
}

select_filesystem() {
	local current_filesystem=${1:-ext4}
	local selected=""

	menu "Filesystem" "Choose the root filesystem." 14 70 4 \
		"ext4" "Default fallback filesystem" \
		"btrfs" "Create @, @home, @var, @snapshots subvolumes with zstd compression"
	selected="$DIALOG_RESULT"
	case $DIALOG_STATUS in
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

	menu "Zram" "Choose whether to enable zram swap." 12 50 2 \
		"yes" "Enable zram" \
		"no" "Disable zram"
	choice="$DIALOG_RESULT"
	case $DIALOG_STATUS in
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
	local status=0
	local MAX_RETRY=3
	local RETRY_COUNT=0

	while (( RETRY_COUNT < MAX_RETRY )); do
		input_box "$title" "$prompt" "$initial_value" 12 76
		value="$DIALOG_RESULT"
		status=$DIALOG_STATUS
		case $status in
			0)
				if [[ -n $value ]]; then
					printf '%s\n' "$value"
					return 0
				fi
				RETRY_COUNT=$((RETRY_COUNT + 1))
				msg "$title" "A value is required."
				;;
			1|255)
				return 1
				;;
			*)
				RETRY_COUNT=$((RETRY_COUNT + 1))
				if (( RETRY_COUNT >= MAX_RETRY )); then
					error_box "$title" "Input failed repeatedly. Returning to the previous menu."
					return 1
				fi
				;;
		esac
		initial_value="$value"
	done

	error_box "$title" "Input retry limit reached. Returning to the previous menu."
	return 1
}

prompt_password() {
	local title=${1:?title is required}
	local first=""
	local second=""
	local status=0
	local MAX_RETRY=3
	local RETRY_COUNT=0

	while (( RETRY_COUNT < MAX_RETRY )); do
		password_box "$title" "Enter the password." 12 76
		first="$DIALOG_RESULT"
		status=$DIALOG_STATUS
		case $status in
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
			RETRY_COUNT=$((RETRY_COUNT + 1))
			msg "$title" "The password cannot be empty."
			continue
		fi

		password_box "$title" "Re-enter the password." 12 76
		second="$DIALOG_RESULT"
		status=$DIALOG_STATUS
		case $status in
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
			RETRY_COUNT=$((RETRY_COUNT + 1))
			msg "$title" "Passwords did not match."
			continue
		fi

		printf '%s\n' "$first"
		return 0
	done

	error_box "$title" "Password retry limit reached. Returning to the previous menu."
	return 1
}

configure_install_profile() {
	local hostname=""
	local timezone=""
	local locale=""
	local keymap=""
	local username=""
	local user_password=""
	local root_password=""
	local boot_mode=""
	local filesystem=""
	local enable_zram=""
	local install_profile=""
	local editor_choice=""
	local include_vscode="false"
	local custom_tools=""
	local custom_checklist=""
	local custom_extra=""
	local secure_boot_mode=""
	local secure_boot_state=""
	local desktop_profile=""
	local display_manager=""
	local greeter_frontend="tuigreet"
	local display_mode=""
	local enable_luks="false"
	local luks_password=""
	local snapshot_provider="none"
	local package_config_warning=""

	refresh_runtime_context || true
	if type package_config_warning_text >/dev/null 2>&1; then
		package_config_warning="$(package_config_warning_text 2>/dev/null || true)"
		if [[ -n $package_config_warning ]]; then
			warning_box "Package Config Warning" "$package_config_warning"
		fi
	fi
	hostname="$(prompt_required_input "Hostname" "Set the system hostname." "$(state_or_default "HOSTNAME" "archlinux")")" || return 1
	timezone="$(select_timezone_value "$(state_or_default "TIMEZONE" "Europe/Istanbul")")" || return 1
	locale="$(select_locale_value "$(state_or_default "LOCALE" "en_US.UTF-8")")" || return 1
	keymap="$(select_keyboard_layout_value "$(state_or_default "KEYMAP" "us")")" || return 1
	username="$(prompt_required_input "Username" "Create the primary user account." "$(state_or_default "USERNAME" "archuser")")" || return 1
	install_profile="$(select_install_profile "$(state_or_default "INSTALL_PROFILE" "daily")")" || return 1
	filesystem="$(select_filesystem "$(state_or_default "FILESYSTEM" "ext4")")" || return 1
	enable_luks="$(select_boolean_value "Encryption" "Enable LUKS2 full-disk encryption for the root filesystem?" "$(state_or_default "ENABLE_LUKS" "false")" "Enable LUKS2" "Disable encryption")" || return 1
	if [[ $enable_luks == "true" ]]; then
		luks_password="$(prompt_password "LUKS Password")" || return 1
	fi
	snapshot_provider="$(select_snapshot_provider "$filesystem" "$install_profile" "$(state_or_default "SNAPSHOT_PROVIDER" "")")" || return 1
	enable_zram="$(select_zram_preference "$(state_or_default "ENABLE_ZRAM" "$ZRAM")")" || return 1
	user_password="$(prompt_password "User Password")" || return 1
	root_password="$(prompt_password "Root Password")" || return 1
	boot_mode="$(state_or_default "BOOT_MODE" "$(detect_boot_mode 2>/dev/null || printf 'uefi')")"
	secure_boot_state="$(state_or_default "CURRENT_SECURE_BOOT_STATE" "unsupported")"
	secure_boot_mode="$(select_secure_boot_mode "$(state_or_default "SECURE_BOOT_MODE" "disabled")" "$boot_mode" "$secure_boot_state")" || return 1

	case $install_profile in
		daily)
			desktop_profile="kde"
			display_mode="auto"
			display_manager="greetd"
			greeter_frontend="tuigreet"
			editor_choice="kate"
			include_vscode="false"
			;;
		dev)
			desktop_profile="$(select_desktop_profile)" || return 1
			display_mode="$(select_display_mode "$desktop_profile" "$(state_or_default "DISPLAY_MODE" "auto")")" || return 1
			display_manager="$(select_display_manager "$desktop_profile")" || return 1
			greeter_frontend="$(select_greeter_frontend "$desktop_profile" "$(state_or_default "GREETER_FRONTEND" "tuigreet")")" || return 1
			editor_choice="$(select_editor_choice "$(state_or_default "EDITOR_CHOICE" "micro")")" || return 1
			include_vscode="$(select_boolean_value "VS Code" "Include Visual Studio Code in the DEV profile?" "$(state_or_default "INCLUDE_VSCODE" "false")" "Install code" "Skip code")" || return 1
			;;
		custom)
			desktop_profile="$(select_desktop_profile)" || return 1
			display_mode="$(select_display_mode "$desktop_profile" "$(state_or_default "DISPLAY_MODE" "auto")")" || return 1
			display_manager="$(select_display_manager "$desktop_profile")" || return 1
			greeter_frontend="$(select_greeter_frontend "$desktop_profile" "$(state_or_default "GREETER_FRONTEND" "tuigreet")")" || return 1
			editor_choice="$(select_editor_choice "$(state_or_default "EDITOR_CHOICE" "nano")")" || return 1
			local _saved_cl
			_saved_cl="$(state_or_default "CUSTOM_CHECKLIST" "")"
			_st()     { [[ -z $_saved_cl || " $_saved_cl " == *" $1 "* ]] && printf 'on' || printf 'off'; }
			_st_off() { [[ -n $_saved_cl && " $_saved_cl " == *" $1 "* ]] && printf 'on' || printf 'off'; }
			checklist_box "Custom Packages" \
				"Select the packages to include in your install. All items are pre-selected by default. Use SPACE to toggle." \
				22 76 12 \
				"git"       "Version control"             "$(_st git)"       \
				"curl"      "HTTP client"                 "$(_st curl)"      \
				"wget"      "File downloader"             "$(_st wget)"      \
				"fastfetch" "System info tool"            "$(_st fastfetch)" \
				"ripgrep"   "Fast recursive grep (rg)"   "$(_st ripgrep)"   \
				"fd"        "Fast find alternative"       "$(_st fd)"        \
				"less"      "Terminal pager"              "$(_st less)"      \
				"man-db"    "Manual page reader"          "$(_st man-db)"    \
				"man-pages" "Linux manual pages"          "$(_st man-pages)" \
				"vscode"    "Visual Studio Code (code)"  "$(_st_off vscode)"
			unset -f _st _st_off
			[[ $DIALOG_STATUS -eq 0 ]] || return 1
			custom_checklist="$DIALOG_RESULT"
			# Extract VS Code from checklist — it is handled via include_vscode flag
			if [[ " $custom_checklist " == *" vscode "* ]]; then
				include_vscode="true"
				custom_checklist="${custom_checklist/ vscode/}"
				custom_checklist="${custom_checklist//vscode /}"
				custom_checklist="${custom_checklist//vscode/}"
			else
				include_vscode="false"
			fi
			local -a _extra_acc=()
			local _extra_saved
			_extra_saved="$(state_or_default "CUSTOM_EXTRA" "")"
			while true; do
				input_box "Additional Packages" \
					"Enter extra packages to install beyond the checklist (space-separated). Leave blank for none." \
					"$_extra_saved" 10 76
				[[ $DIALOG_STATUS -eq 0 ]] || return 1
				local _extra_input="$DIALOG_RESULT"
				_extra_saved=""
				if [[ -z $_extra_input ]]; then
					break
				fi
				local -a _extra_arr=() _bad_pkgs=() _good_pkgs=()
				read -r -a _extra_arr <<< "$_extra_input"
				local _pkg
				for _pkg in "${_extra_arr[@]}"; do
					[[ -n $_pkg ]] || continue
					if pacman -Sp "$_pkg" >/dev/null 2>&1; then
						_good_pkgs+=("$_pkg")
					else
						_bad_pkgs+=("$_pkg")
					fi
				done
				if (( ${#_bad_pkgs[@]} > 0 )); then
					msg "Invalid Packages" "The following packages were not found in the repositories and will not be added:\n\n  ${_bad_pkgs[*]}\n\nPlease re-enter. Only valid package names are accepted."
					_extra_saved="$_extra_input"
					continue
				fi
				_extra_acc+=("${_good_pkgs[@]}")
				confirm "Add More Packages" "All packages validated.\n\nCurrently queued: ${_extra_acc[*]}\n\nAdd more extra packages?" || break
			done
			custom_extra="${_extra_acc[*]}"
			custom_tools="${custom_checklist}${custom_extra:+ $custom_extra}"
			;;
		*)
			return 1
			;;
	esac

	if [[ $desktop_profile == "none" ]]; then
		display_mode="auto"
		display_manager="none"
		greeter_frontend="tuigreet"
	fi

	set_state "HOSTNAME" "$hostname" || return 1
	set_state "TIMEZONE" "$timezone" || return 1
	set_state "LOCALE" "$locale" || return 1
	set_state "KEYMAP" "$keymap" || return 1
	set_state "USERNAME" "$username" || return 1
	set_state "INSTALL_PROFILE" "$install_profile" || return 1
	set_state "EDITOR_CHOICE" "$editor_choice" || return 1
	set_state "INCLUDE_VSCODE" "$include_vscode" || return 1
	set_state "CUSTOM_TOOLS" "$custom_tools" || return 1
	set_state "CUSTOM_CHECKLIST" "$custom_checklist" || return 1
	set_state "CUSTOM_EXTRA" "$custom_extra" || return 1
	set_state "SECURE_BOOT_MODE" "$secure_boot_mode" || return 1
	set_state "FILESYSTEM" "$filesystem" || return 1
	set_state "ENABLE_LUKS" "$enable_luks" || return 1
	set_state "LUKS_MAPPER_NAME" "cryptroot" || return 1
	set_state "SNAPSHOT_PROVIDER" "$snapshot_provider" || return 1
	set_state "ENABLE_ZRAM" "$enable_zram" || return 1
	set_state "DESKTOP_PROFILE" "$desktop_profile" || return 1
	set_state "DISPLAY_MODE" "$display_mode" || return 1
	set_state "DISPLAY_MANAGER" "$display_manager" || return 1
	set_state "GREETER_FRONTEND" "$greeter_frontend" || return 1
	set_state "BOOT_MODE" "$boot_mode" || return 1
	INSTALL_USER_PASSWORD="$user_password"
	INSTALL_ROOT_PASSWORD="$root_password"
	INSTALL_LUKS_PASSWORD="$luks_password"
	if type sync_install_config_json >/dev/null 2>&1; then
		sync_install_config_json >/dev/null 2>&1 || true
	fi

	msg "Profile Saved" "Installation profile updated.\n\nHostname: $hostname\nTimezone: $timezone\nLocale: $locale\nKeyboard: $keymap\nUser: $username\nInstall profile: $(install_profile_label "$install_profile")\nEditor: $(editor_choice_label "$editor_choice")\nVS Code: $include_vscode\nSecure Boot mode: $(secure_boot_mode_label "$secure_boot_mode")\nFilesystem: $filesystem\nEncryption: $enable_luks\nSnapshots: $(snapshot_provider_label "$snapshot_provider")\nZram: $enable_zram\nDesktop: $(desktop_profile_label "$desktop_profile")\nDisplay mode: $(display_mode_label "$display_mode")\nDisplay manager: $(display_manager_label "$display_manager")\nGreeter frontend: $(greeter_frontend_label "$greeter_frontend")\nBoot mode: $(boot_mode_status_label "$boot_mode" "$secure_boot_state")\nUser password: set\nRoot password: set"
}

validate_install_profile() {
	local missing=()

	has_state "HOSTNAME" || missing+=("hostname")
	has_state "TIMEZONE" || missing+=("timezone")
	has_state "LOCALE" || missing+=("locale")
	has_state "KEYMAP" || missing+=("keyboard layout")
	has_state "USERNAME" || missing+=("user")
	[[ -n $INSTALL_USER_PASSWORD ]] || missing+=("user password")
	[[ -n $INSTALL_ROOT_PASSWORD ]] || missing+=("root password")
	if [[ $(state_or_default "ENABLE_LUKS" "false") == "true" && -z ${INSTALL_LUKS_PASSWORD:-} ]]; then
		missing+=("LUKS password")
	fi

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
	msg "Developer Mode" "DEV_MODE is now set to: $DEV_MODE\n\nInstall UI mode: $INSTALL_UI_MODE\n\nDEV_MODE=true shows live terminal logs. DEV_MODE=false uses the dialog live log window."
}

show_state_summary() {
	local disk
	local boot_mode
	local efi_partition
	local root_partition
	local hostname
	local timezone
	local locale
	local keymap
	local username
	local filesystem
	local enable_zram
	local desktop_profile
	local display_mode
	local resolved_display_mode
	local display_manager
	local greeter_frontend
	local disk_type
	local install_scenario
	local enable_luks
	local snapshot_provider
	local secure_boot_state
	local secure_boot_mode
	local environment_summary_value
	local gpu_label_value
	local install_profile_value
	local user_password_state
	local root_password_state

	disk="$(get_state "DISK" 2>/dev/null || printf 'Not selected')"
	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || detect_boot_mode 2>/dev/null || printf 'bios')"
	efi_partition="$(get_state "EFI_PART" 2>/dev/null || printf 'Not created')"
	root_partition="$(get_state "ROOT_PART" 2>/dev/null || printf 'Not created')"
	hostname="$(state_or_default "HOSTNAME" "archlinux")"
	timezone="$(state_or_default "TIMEZONE" "Europe/Istanbul")"
	locale="$(state_or_default "LOCALE" "en_US.UTF-8")"
	keymap="$(state_or_default "KEYMAP" "us")"
	username="$(state_or_default "USERNAME" "Not configured")"
	filesystem="$(state_or_default "FILESYSTEM" "ext4")"
	disk_type="$(normalize_disk_type "$(state_or_default "DISK_TYPE" "unknown")")"
	install_scenario="$(state_or_default "INSTALL_SCENARIO" "wipe")"
	enable_luks="$(state_or_default "ENABLE_LUKS" "false")"
	snapshot_provider="$(state_or_default "SNAPSHOT_PROVIDER" "none")"
	enable_zram="$(state_or_default "ENABLE_ZRAM" "false")"
	desktop_profile="$(state_or_default "DESKTOP_PROFILE" "none")"
	display_mode="$(state_or_default "DISPLAY_MODE" "auto")"
	resolved_display_mode="$(state_or_default "RESOLVED_DISPLAY_MODE" "auto")"
	display_manager="$(state_or_default "DISPLAY_MANAGER" "none")"
	greeter_frontend="$(state_or_default "GREETER_FRONTEND" "tuigreet")"
	secure_boot_state="$(state_or_default "CURRENT_SECURE_BOOT_STATE" "unsupported")"
	secure_boot_mode="$(state_or_default "SECURE_BOOT_MODE" "disabled")"
	environment_summary_value="$(safe_runtime_environment_summary)"
	gpu_label_value="$(state_or_default "GPU_LABEL" "Generic")"
	install_profile_value="$(state_or_default "INSTALL_PROFILE" "daily")"
	user_password_state="not set"
	root_password_state="not set"
	[[ -n $INSTALL_USER_PASSWORD ]] && user_password_state="set"
	[[ -n $INSTALL_ROOT_PASSWORD ]] && root_password_state="set"

	msg "Installer State" "Saved state:\n\nEnvironment: $environment_summary_value\nGPU: $gpu_label_value\nDisk: $disk\nDisk type: $(post_install_disk_type_label)\nDisk strategy: $install_scenario\nBoot mode: $(boot_mode_status_label "$boot_mode" "$secure_boot_state")\nSecure Boot mode: $(secure_boot_mode_label "$secure_boot_mode")\nEFI: $efi_partition\nRoot: $root_partition\nHostname: $hostname\nTimezone: $timezone\nLocale: $locale\nKeyboard: $keymap\nUser: $username\nInstall profile: $(install_profile_label "$install_profile_value")\nFilesystem: $filesystem\nEncryption: $enable_luks\nSnapshots: $(snapshot_provider_label "$snapshot_provider")\nZram: $enable_zram\nDesktop: $(desktop_profile_label "$desktop_profile")\nDisplay mode: $(display_mode_label "$display_mode")\nResolved mode: $(display_mode_label "$resolved_display_mode")\nDisplay manager: $(display_manager_label "$display_manager")\nGreeter frontend: $(greeter_frontend_label "$greeter_frontend")\nSafe mode: $INSTALL_SAFE_MODE\nUser password: $user_password_state\nRoot password: $root_password_state\nDEV_MODE: $DEV_MODE\nUI mode: $INSTALL_UI_MODE" 29 82
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

	message="$(installer_context_header)\n\nThis will prepare a bootable Arch Linux system on:\n\n$disk\n\nDisk type: $(post_install_disk_type_label)\nDisk strategy: $(state_or_default "INSTALL_SCENARIO" "wipe")\nBoot mode: $(boot_mode_status_label "$(state_or_default "BOOT_MODE" "bios")" "$(state_or_default "CURRENT_SECURE_BOOT_STATE" "unsupported")")\nSecure Boot mode: $(secure_boot_mode_label "$(state_or_default "SECURE_BOOT_MODE" "disabled")")\nHostname: $(state_or_default "HOSTNAME" "archlinux")\nTimezone: $(state_or_default "TIMEZONE" "Europe/Istanbul")\nLocale: $(state_or_default "LOCALE" "en_US.UTF-8")\nKeyboard: $(state_or_default "KEYMAP" "us")\nUser: $(state_or_default "USERNAME" "archuser")\nInstall profile: $(install_profile_label "$(state_or_default "INSTALL_PROFILE" "daily")")\nFilesystem: $(state_or_default "FILESYSTEM" "ext4")\nEncryption: $(state_or_default "ENABLE_LUKS" "false")\nSnapshots: $(snapshot_provider_label "$(state_or_default "SNAPSHOT_PROVIDER" "none")")\nZram: $(state_or_default "ENABLE_ZRAM" "false")\nDesktop: $(desktop_profile_label "$(state_or_default "DESKTOP_PROFILE" "none")")\nDisplay mode: $(display_mode_label "$(state_or_default "DISPLAY_MODE" "auto")")\nDisplay manager: $(display_manager_label "$(state_or_default "DISPLAY_MANAGER" "none")")\nGreeter frontend: $(greeter_frontend_label "$(state_or_default "GREETER_FRONTEND" "tuigreet")")\nSafe mode: $(state_or_default "INSTALL_SAFE_MODE" "$INSTALL_SAFE_MODE")\n\nDestructive steps may erase existing data."
	if flag_enabled "$DEV_MODE"; then
		message+="\n\nDev mode flags:\nSKIP_PARTITION=$SKIP_PARTITION\nSKIP_PACSTRAP=$SKIP_PACSTRAP\nSKIP_CHROOT=$SKIP_CHROOT\nINSTALL_UI_MODE=$INSTALL_UI_MODE"
	fi

	if ! confirm "Confirm Installation" "$message\n\nContinue?" 18 76; then
		return 1
	fi

	if ! require_yes_confirmation "Final Confirmation" "Review complete. Type YES to start installation on $disk."; then
		warning_box "Confirmation Failed" "Exact confirmation text was not entered. Installation was cancelled."
		return 1
	fi

	return 0
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
		step_box "Starting Installer" "Launching the install core in the background. The dialog log view stays open until the install finishes."
		run_install_with_dialog
		status=$?
	else
		run_install
		status=$?
	fi

	if [[ $status -ne 0 && $status -ne 130 && $status -ne 255 ]]; then
		show_install_failure_dialog "${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}" || true
	fi

	if [[ $status -eq 0 ]]; then
		show_post_install_screen "$status" || true
	fi

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
	local MAX_RETRY=3
	local RETRY_COUNT=0
	local -a dynamic_entries=()

	while (( RETRY_COUNT < MAX_RETRY )); do
		dynamic_entries=()
		if type emit_menu_entries >/dev/null 2>&1; then
			mapfile -t dynamic_entries < <(emit_menu_entries disk)
		fi
		menu "Disk Setup" "$(installer_context_header)\n\nCurrent disk: $(current_disk_label)" 18 82 $((6 + (${#dynamic_entries[@]} / 2))) \
			"select" "Discover disks and choose an install target" \
			"clear" "Clear the saved disk selection" \
			"${dynamic_entries[@]}" \
			"back" "Return to the main menu"
		choice="$DIALOG_RESULT"
		status=$DIALOG_STATUS

		case $status in
			0)
				RETRY_COUNT=0
				;;
			1|255)
				return 0
				;;
			*)
				RETRY_COUNT=$((RETRY_COUNT + 1))
				if (( RETRY_COUNT >= MAX_RETRY )); then
					error_box "Navigation Error" "The disk menu failed repeatedly. Switching back to the main menu."
					return 1
				fi
				error_box "Navigation Error" "The disk menu returned an unexpected dialog status: $status"
				continue
				;;
		esac

		case "$choice" in
			select)
				local select_status=0
				local selected_disk=""
				if type run_hooks >/dev/null 2>&1; then
					run_hooks pre_disk || true
				fi
				select_disk
				select_status=$?
				if type run_hooks >/dev/null 2>&1; then
					run_hooks post_disk || true
				fi
				selected_disk="$(get_state "DISK" 2>/dev/null || true)"
				if [[ $select_status -eq 0 && -n $selected_disk ]]; then
					set_menu_default_item "config"
					return 0
				fi
				;;
			clear)
				unset_state "DISK"
				unset_state "INSTALL_SCENARIO"
				unset_state "FORMAT_ROOT"
				unset_state "FORMAT_EFI"
				unset_state "EFI_PART"
				unset_state "ROOT_PART"
				msg "Disk Cleared" "The saved disk and partition state were removed."
				;;
			back)
				return 0
				;;
			*)
				if type run_menu_entry_handler >/dev/null 2>&1; then
					run_menu_entry_handler disk "$choice" || true
				fi
				;;
		esac
	done

	error_box "Navigation Error" "Disk menu retry limit reached. Returning to the main menu."
	return 1
}

main() {
	local choice=""
	local status=0
	local MAX_RETRY=3
	local RETRY_COUNT=0
	local -a dynamic_entries=()

	if ! require_dialog >/dev/null 2>&1; then
		set_ui_mode tty
		log_ui_error "[UI ERROR] dialog is unavailable at startup; using TTY fallback"
	fi
	ensure_executor_loaded || exit 1
	ensure_state_file || exit 1
	load_runtime_preferences || exit 1
	if ! require_dialog >/dev/null 2>&1; then
		set_ui_mode tty
		apply_runtime_mode || true
		log_ui_error "[UI ERROR] dialog is unavailable after loading preferences; using TTY fallback"
	fi
	prepare_live_console || true

	# Let user choose UI mode (Dialog or TTY) before anything else.
	if require_dialog >/dev/null 2>&1 && [[ ${UI_MODE:-dialog} == "dialog" ]]; then
		menu "Installer Mode" "Welcome to the ArchInstall Framework.\n\nSelect how you want to interact with the installer:" 12 60 2 \
			"dialog" "Graphical TUI  (recommended)" \
			"tty"    "Plain text / debug mode"
		if [[ $DIALOG_STATUS -eq 0 && $DIALOG_RESULT == "tty" ]]; then
			set_ui_mode tty
			apply_runtime_mode || true
		fi
	fi

	warn_if_low_live_iso_space || true
	refresh_runtime_context || true

	while (( RETRY_COUNT < MAX_RETRY )); do
		dynamic_entries=()
		if type emit_menu_entries >/dev/null 2>&1; then
			mapfile -t dynamic_entries < <(emit_menu_entries main)
		fi
		if [[ $(state_or_default "DISK" "") == "" ]]; then
			set_menu_default_item "disk"
		fi
		menu "Main Menu" "$(installer_context_header)\n\nChoose an installer action." 18 82 $((7 + (${#dynamic_entries[@]} / 2))) \
			"disk"   "Disk setup and target selection" \
			"config" "Configure hostname, profile, password, and options" \
			"install" "Start installation (requires disk and config)" \
			"state"  "Show saved installer state" \
			"${dynamic_entries[@]}" \
			"exit"   "Exit the installer"
		choice="$DIALOG_RESULT"
		status=$DIALOG_STATUS

		case $status in
			0)
				RETRY_COUNT=0
				;;
			1|255)
				break
				;;
			*)
				RETRY_COUNT=$((RETRY_COUNT + 1))
				if (( RETRY_COUNT >= MAX_RETRY )); then
					error_box "Navigation Error" "The main menu failed repeatedly. Exiting the installer."
					exit 1
				fi
				error_box "Navigation Error" "The main menu returned an unexpected dialog status: $status"
				continue
				;;
		esac

		case "$choice" in
			disk)
				show_disk_menu
				;;
			config)
				configure_install_profile || true
				;;
			install)
				run_install_flow
				;;
			state)
				show_state_summary
				;;
			exit)
				break
				;;
			*)
				if type run_menu_entry_handler >/dev/null 2>&1; then
					run_menu_entry_handler main "$choice" || true
				fi
				;;
		esac
	done

	clear_screen
}

main "$@"