#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCHINSTALL_LOG=${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}
ARCHINSTALL_INSTALL_SUCCESS=${ARCHINSTALL_INSTALL_SUCCESS:-false}
ARCHINSTALL_CLEANUP_ACTIVE=${ARCHINSTALL_CLEANUP_ACTIVE:-false}
ARCHINSTALL_PROGRESS_LOG=${ARCHINSTALL_PROGRESS_LOG:-/tmp/archinstall_progress.log}
PACMAN_OPTS=${PACMAN_OPTS:---noconfirm --needed}
export PACMAN_OPTS
DEV_MODE=${DEV_MODE:-false}
INSTALL_SAFE_MODE=${INSTALL_SAFE_MODE:-true}
SKIP_PARTITION=${SKIP_PARTITION:-false}
SKIP_PACSTRAP=${SKIP_PACSTRAP:-false}
SKIP_CHROOT=${SKIP_CHROOT:-false}
INSTALL_UI_MODE=${INSTALL_UI_MODE:-plain}

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
# shellcheck source=installer/modules/desktop.sh
safe_source_module "$SCRIPT_DIR/modules/desktop.sh" || true
# shellcheck source=installer/modules/secureboot.sh
safe_source_module "$SCRIPT_DIR/modules/secureboot.sh" || true
# shellcheck source=installer/modules/profiles.sh
safe_source_module "$SCRIPT_DIR/modules/profiles.sh" || true
# shellcheck source=installer/modules/network.sh
safe_source_module "$SCRIPT_DIR/modules/network.sh" || true
# shellcheck source=installer/modules/packages.sh
safe_source_module "$SCRIPT_DIR/modules/packages.sh" || true
# shellcheck source=installer/modules/luks.sh
safe_source_module "$SCRIPT_DIR/modules/luks.sh" || true
# shellcheck source=installer/modules/snapshots.sh
safe_source_module "$SCRIPT_DIR/modules/snapshots.sh" || true
# shellcheck source=installer/modules/disk/layout.sh
safe_source_module "$SCRIPT_DIR/modules/disk/layout.sh" || true
# shellcheck source=installer/modules/disk/space.sh
safe_source_module "$SCRIPT_DIR/modules/disk/space.sh" || true
# shellcheck source=installer/modules/system/network.sh
safe_source_module "$SCRIPT_DIR/modules/system/network.sh" || true
# shellcheck source=installer/modules/system/audio.sh
safe_source_module "$SCRIPT_DIR/modules/system/audio.sh" || true
# shellcheck source=installer/modules/system/bluetooth.sh
safe_source_module "$SCRIPT_DIR/modules/system/bluetooth.sh" || true

if type load_installer_plugins >/dev/null 2>&1; then
	load_installer_plugins || true
fi
if type archinstall_register_builtin_modules >/dev/null 2>&1; then
	archinstall_register_builtin_modules || true
fi
if type sync_install_config_json >/dev/null 2>&1; then
	sync_install_config_json >/dev/null 2>&1 || true
fi

flag_enabled() {
	case ${1:-false} in
		1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
			return 0
			;;
		*)
			return 1
			;;
	esac
}

install_ui_uses_dialog() {
	[[ ${INSTALL_UI_MODE:-plain} == "dialog" ]]
}

build_pacman_opts_array() {
	local -n options_ref=${1:?options reference is required}

	read -r -a options_ref <<< "${PACMAN_OPTS:---noconfirm --needed}"
}

append_unique_items() {
	local -n target_ref=${1:?target reference is required}
	local item=""
	local existing=""
	local is_duplicate="false"

	shift
	for item in "$@"; do
		[[ -n $item ]] || continue
		is_duplicate="false"
		for existing in "${target_ref[@]}"; do
			if [[ $existing == "$item" ]]; then
				is_duplicate="true"
				break
			fi
		done
		if [[ $is_duplicate != "true" ]]; then
			target_ref+=("$item")
		fi
	done
}

run_pacman_step_with_retry() {
	local step=${1:?step description is required}
	local max_attempts=${2:?max attempts is required}
	local operation=${3:?pacman operation is required}
	local -a pacman_opts=()

	shift 3
	build_pacman_opts_array pacman_opts
	run_step_with_retry "$step" "$max_attempts" pacman "$operation" "${pacman_opts[@]}" "$@"
}

run_optional_pacman_step_with_retry() {
	local step=${1:?step description is required}
	local max_attempts=${2:?max attempts is required}
	local operation=${3:?pacman operation is required}
	local -a pacman_opts=()

	shift 3
	build_pacman_opts_array pacman_opts
	run_optional_step_with_retry "$step" "$max_attempts" pacman "$operation" "${pacman_opts[@]}" "$@"
}

render_command() {
	local rendered_command=""

	printf -v rendered_command '%q ' "$@"
	printf '%s\n' "${rendered_command% }"
}

join_by_comma() {
	local joined=""
	local item=""

	for item in "$@"; do
		if [[ -z $joined ]]; then
			joined=$item
		else
			joined+=",$item"
		fi
	done

	printf '%s\n' "$joined"
}

detect_disk_type() {
	local disk=${1:?disk is required}
	local disk_name=""
	local rotational_path=""
	local rotational_value=""

	disk_name="$(basename "$disk")"
	if [[ $disk_name == nvme* ]]; then
		printf 'nvme\n'
		return 0
	fi

	rotational_path="/sys/block/$disk_name/queue/rotational"
	if [[ -r $rotational_path ]]; then
		read -r rotational_value < "$rotational_path"
		if [[ $rotational_value == "0" ]]; then
			printf 'ssd\n'
		else
			printf 'hdd\n'
		fi
		return 0
	fi

	if rotational_value="$(lsblk -dn -o ROTA "$disk" 2>> "$ARCHINSTALL_LOG" || true)"; then
		if [[ $rotational_value == "0" ]]; then
			printf 'ssd\n'
			return 0
		fi
		if [[ $rotational_value == "1" ]]; then
			printf 'hdd\n'
			return 0
		fi
	fi

	printf 'unknown\n'
}

ext4_mount_options() {
	local disk_type=${1:-unknown}
	local -a options=(defaults noatime)

	if [[ $disk_type == "ssd" || $disk_type == "nvme" ]]; then
		options+=(discard=async)
	fi

	join_by_comma "${options[@]}"
}

btrfs_mount_options() {
	local subvolume=${1:?subvolume is required}
	local disk_type=${2:-unknown}
	local -a options=("subvol=$subvolume" compress=zstd noatime)

	if [[ $disk_type == "ssd" || $disk_type == "nvme" ]]; then
		options+=(discard=async)
	fi

	join_by_comma "${options[@]}"
}

build_pacstrap_package_list() {
	local boot_mode=${1:?boot mode is required}
	local filesystem=${2:?filesystem is required}
	local enable_zram=${3:?zram flag is required}
	local -n package_ref=${4:?package reference is required}
	local desktop_profile=${5:-none}
	local display_manager=${6:-none}
	local display_mode=${7:-auto}
	local install_profile=${8:-daily}
	local editor_choice=${9:-nano}
	local include_vscode=${10:-false}
	local custom_tools=${11:-}
	local environment_vendor=${12:-baremetal}
	local gpu_vendor=${13:-generic}
	local secure_boot_mode=${14:-disabled}
	local greeter_frontend=${15:-tuigreet}
	local snapshot_provider="$(get_state "SNAPSHOT_PROVIDER" 2>/dev/null || printf 'none')"
	local enable_luks="$(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false')"

	package_ref=()
	if declare -F resolve_package_strategy >/dev/null 2>&1; then
		resolve_package_strategy "$boot_mode" "$filesystem" "$enable_zram" "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" "$desktop_profile" "$display_manager" "$display_mode" "$environment_vendor" "$gpu_vendor" "$secure_boot_mode" "$greeter_frontend" "$snapshot_provider" "$enable_luks" package_ref || return 1
		return 0
	fi

	get_final_packages "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" package_ref || return 1
}

normalize_filesystem() {
	case ${1:-ext4} in
		ext4|btrfs)
			printf '%s\n' "$1"
			return 0
			;;
		*)
			printf 'ext4\n'
			return 0
			;;
	esac
}

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
	local boot_mode=""
	local filesystem=""
	local enable_luks=""

	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || detect_boot_mode 2>/dev/null || printf 'uefi')"
	filesystem="$(normalize_filesystem "$(get_state "FILESYSTEM" 2>/dev/null || printf 'ext4')")"
	enable_luks="$(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false')"

	for cmd in lsblk wipefs parted partprobe mkfs.ext4 mount umount pacman pacstrap ping blkid arch-chroot tee tail findmnt genfstab mountpoint; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done
	if [[ ${UI_MODE:-dialog} == "dialog" ]]; then
		command -v dialog >/dev/null 2>&1 || missing+=("dialog")
	fi

	if [[ $boot_mode == "uefi" ]]; then
		for cmd in mkfs.fat bootctl; do
			command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
		done
	else
		for cmd in grub-install grub-mkconfig; do
			command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
		done
	fi

	if [[ $filesystem == "btrfs" ]]; then
		for cmd in mkfs.btrfs btrfs; do
			command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
		done
	fi
	if flag_enabled "$enable_luks"; then
		command -v cryptsetup >/dev/null 2>&1 || missing+=("cryptsetup")
	fi

	if [[ ${#missing[@]} -eq 0 ]]; then
		return 0
	fi

	error_box "Missing Commands" "Install the required tools before continuing:\n\n${missing[*]}"
	return 1
}

log_line() {
	local message=${1:-}

	printf '[%s] %s\n' "$(date '+%F %T')" "$message" >> "$ARCHINSTALL_LOG"
	if [[ -n ${ARCHINSTALL_PROGRESS_LOG:-} && ${ARCHINSTALL_PROGRESS_LOG:-} != "$ARCHINSTALL_LOG" ]]; then
		printf '[%s] %s\n' "$(date '+%F %T')" "$message" >> "$ARCHINSTALL_PROGRESS_LOG" 2>/dev/null || true
	fi
}

log_stage() {
	local percent=${1:?percent required}
	local label=${2:?label required}
	local ts
	ts="$(date '+%F %T')"
	printf '[%s] [STAGE:%s] %s\n' "$ts" "$percent" "$label" >> "$ARCHINSTALL_LOG"
	if [[ -n ${ARCHINSTALL_PROGRESS_LOG:-} && ${ARCHINSTALL_PROGRESS_LOG:-} != "$ARCHINSTALL_LOG" ]]; then
		printf '[STAGE:%s] %s\n' "$percent" "$label" >> "$ARCHINSTALL_PROGRESS_LOG" 2>/dev/null || true
	fi
}

tee_install_logs() {
	if [[ -n ${ARCHINSTALL_PROGRESS_LOG:-} && ${ARCHINSTALL_PROGRESS_LOG:-} != "$ARCHINSTALL_LOG" ]]; then
		tee -a "$ARCHINSTALL_LOG" "$ARCHINSTALL_PROGRESS_LOG"
		return
	fi

	tee -a "$ARCHINSTALL_LOG"
}

sanitize_stream() {
	if command -v stdbuf >/dev/null 2>&1; then
		stdbuf -oL tr -cd '\11\12\15\40-\176'
		return
	fi

	tr -cd '\11\12\15\40-\176'
}

print_install_info() {
	printf '[*] %s\n' "$1"
}

print_install_error() {
	printf '[!] %s\n' "$1" >&2
}

run_logged_command() {
	log_line "Command: $(render_command "$@")"

	if install_ui_uses_dialog; then
		"$@" 2>&1 | sanitize_stream | tee_install_logs >/dev/null
		return $?
	fi

	"$@" 2>&1 | sanitize_stream | tee_install_logs
}

run_logged_shell_command() {
	local command_string=${1:?command string is required}

	log_line "Command: bash -lc $command_string"

	if install_ui_uses_dialog; then
		bash -lc "$command_string" 2>&1 | sanitize_stream | tee_install_logs >/dev/null
		return $?
	fi

	bash -lc "$command_string" 2>&1 | sanitize_stream | tee_install_logs
}

cleanup_mounts() {
	log_line "[DEBUG] cleanup_mounts requested"
	if mountpoint -q /mnt 2>> "$ARCHINSTALL_LOG"; then
		log_line "[DEBUG] Mount state before recursive unmount:"
		findmnt -R /mnt >> "$ARCHINSTALL_LOG" 2>&1 || true
	fi
	umount -R /mnt >> "$ARCHINSTALL_LOG" 2>&1 || true
	if declare -F close_luks_root_device >/dev/null 2>&1; then
		close_luks_root_device "$(get_state "LUKS_MAPPER_NAME" 2>/dev/null || printf 'cryptroot')" >> "$ARCHINSTALL_LOG" 2>&1 || true
	fi

	return 0
}

cleanup_install() {
	if [[ ${ARCHINSTALL_CLEANUP_ACTIVE:-false} == true && ${ARCHINSTALL_INSTALL_SUCCESS:-false} != true ]]; then
		log_line "Running post-install cleanup (unmounting)"
		cleanup_mounts || true
		ARCHINSTALL_CLEANUP_ACTIVE=false
	fi
}

on_install_sigint() {
	# Called only on genuine Ctrl-C / SIGINT.  Set flag then exit so the
	# EXIT trap (cleanup_install) handles the actual umount cleanup once.
	if [[ ${ARCHINSTALL_CLEANUP_ACTIVE:-false} == true ]]; then
		log_line "[WARN] Installation interrupted by user"
	fi
	exit 130
}

show_install_error() {
	local step=${1:-"Unknown step"}
	local excerpt

	excerpt="$(tail -n 50 "$ARCHINSTALL_LOG" 2>/dev/null || true)"
	print_install_error "Installation failed during: $step"
	if [[ -n $excerpt ]]; then
		printf '%s\n' "$excerpt" >&2
	fi
	print_install_error "Full log: $ARCHINSTALL_LOG"
}

run_step() {
	local step=${1:?step description is required}

	shift
	install_ui_uses_dialog || print_install_info "$step"
	log_line "[STEP] $step"

	if run_logged_command "$@"; then
		log_line "[ OK ] $step"
		return 0
	fi

	log_line "[FAIL] $step"
	show_install_error "$step"
	return 1
}

run_shell_step() {
	local step=${1:?step description is required}
	local command_string=${2:?command string is required}

	install_ui_uses_dialog || print_install_info "$step"
	log_line "[STEP] $step"

	if run_logged_shell_command "$command_string"; then
		log_line "[ OK ] $step"
		return 0
	fi

	log_line "[FAIL] $step"
	show_install_error "$step"
	return 1
}

run_optional_step() {
	local step=${1:?step description is required}

	shift
	install_ui_uses_dialog || print_install_info "$step"
	log_line "[STEP] $step"

	if run_logged_command "$@"; then
		log_line "[ OK ] $step"
		return 0
	fi

	log_line "[WARN] Non-critical step failed: $step"
	return 0
}

run_optional_step_with_retry() {
	local step=${1:?step description is required}
	local max_attempts=${2:?max attempts is required}
	local attempt=1

	shift 2

	while (( attempt <= max_attempts )); do
		install_ui_uses_dialog || print_install_info "$step (attempt $attempt/$max_attempts)"
		log_line "[STEP] $step (attempt $attempt/$max_attempts)"

		if run_logged_command "$@"; then
			log_line "[ OK ] $step"
			return 0
		fi

		if (( attempt == max_attempts )); then
			log_line "[WARN] Non-critical step failed after retries: $step"
			return 0
		fi

		log_line "[WARN] Retrying non-critical step: $step"
		attempt=$((attempt + 1))
	done
}

run_optional_shell_step() {
	local step=${1:?step description is required}
	local command_string=${2:?command string is required}

	install_ui_uses_dialog || print_install_info "$step"
	log_line "[STEP] $step"

	if run_logged_shell_command "$command_string"; then
		log_line "[ OK ] $step"
		return 0
	fi

	log_line "[WARN] Non-critical shell step failed: $step"
	return 0
}

run_step_with_retry() {
	local step=${1:?step description is required}
	local max_attempts=${2:?max attempts is required}
	local attempt=1

	shift 2

	while (( attempt <= max_attempts )); do
		install_ui_uses_dialog || print_install_info "$step (attempt $attempt/$max_attempts)"
		log_line "[STEP] $step (attempt $attempt/$max_attempts)"

		if run_logged_command "$@"; then
			log_line "[ OK ] $step"
			return 0
		fi

		if (( attempt == max_attempts )); then
			log_line "[FAIL] $step"
			show_install_error "$step"
			return 1
		fi

		log_line "[WARN] Retrying: $step"
		attempt=$((attempt + 1))
	done
}

filter_valid_packages() {
	# Remove packages that are not resolvable in the current pacman DB.
	# pacman -Sp resolves a package name against sync DBs without downloading.
	# Unknown/typo'd names are logged as warnings and skipped.
	local -n _fvp_in=${1:?input ref required}
	local -n _fvp_out=${2:?output ref required}
	local pkg=""

	_fvp_out=()
	for pkg in "${_fvp_in[@]}"; do
		[[ -n $pkg ]] || continue
		if pacman -Sp "$pkg" >/dev/null 2>&1; then
			_fvp_out+=("$pkg")
		else
			log_line "[WARN] Package not found in repos, skipping: $pkg"
		fi
	done
}

run_pacstrap_install() {
	local -a mandatory_packages=(base linux linux-firmware mkinitcpio sudo)
	local -a packages=("$@")
	local -a validated_packages=()

	append_unique_items packages "${mandatory_packages[@]}"
	log_line "[DEBUG] Mandatory pacstrap packages: ${mandatory_packages[*]}"
	log_line "[DEBUG] Pre-validation pacstrap package list: ${packages[*]}"
	filter_valid_packages packages validated_packages
	log_line "[DEBUG] Final pacstrap package list: ${validated_packages[*]}"
	# -K initialises an empty pacman keyring inside the new root so the installed
	# system is not dependent on the live-ISO keyring state.
	run_step_with_retry "Installing the base Arch Linux packages" 3 \
		pacstrap -K /mnt "${validated_packages[@]}" --noconfirm
}

get_partition_uuid() {
	local partition=${1:?partition is required}
	local uuid=""

	uuid="$(blkid -s UUID -o value "$partition" 2>> "$ARCHINSTALL_LOG" || true)"
	if [[ -z $uuid ]]; then
		print_install_error "Could not determine the UUID for: $partition"
		return 1
	fi

	printf '%s\n' "$uuid"
}

log_partition_metadata() {
	local root_partition=${1:?root partition is required}
	local efi_partition=${2-}

	if [[ -n $efi_partition ]]; then
		run_optional_step "Capturing block metadata" blkid "$efi_partition" "$root_partition"
		return 0
	fi

	run_optional_step "Capturing block metadata" blkid "$root_partition"
	return 0
}

log_mounted_filesystems() {
	local filesystem=${1:?filesystem is required}

	run_optional_step "Recording root mount details" findmnt -no TARGET,SOURCE,OPTIONS /mnt
	if [[ $filesystem == "btrfs" ]]; then
		run_optional_step "Recording home mount details" findmnt -no TARGET,SOURCE,OPTIONS /mnt/home
		run_optional_step "Recording var mount details" findmnt -no TARGET,SOURCE,OPTIONS /mnt/var
		run_optional_step "Recording snapshots mount details" findmnt -no TARGET,SOURCE,OPTIONS /mnt/.snapshots
	fi
}

write_target_fstab() {
	local filesystem=${1:?filesystem is required}
	local disk_type=${2:?disk type is required}
	local root_partition=${3:?root partition is required}
	local expected_root_source=${4-}
	local efi_partition=${5-}
	local fstab_path=/mnt/etc/fstab
	validate_target_mount "$root_partition" "$expected_root_source" || return 1
	case $filesystem in
		ext4|btrfs)
			;;
		*)
			print_install_error "Unsupported filesystem for fstab generation: $filesystem"
			return 1
			;;
	esac
	run_shell_step "Generating fstab" "mkdir -p /mnt/etc && genfstab -U /mnt > '$fstab_path'"
	local fstab_status=$?
	if [[ $fstab_status -ne 0 ]]; then
		return "$fstab_status"
	fi

	log_line "[DEBUG] Generated fstab:"
	if [[ -f $fstab_path ]]; then
		sanitize_stream < "$fstab_path" >> "$ARCHINSTALL_LOG"
	fi

	return 0
}

format_root_filesystem() {
	local filesystem=${1:?filesystem is required}
	local root_partition=${2:?root partition is required}

	case $filesystem in
		ext4)
			run_step "Formatting the root partition as ext4" mkfs.ext4 -F "$root_partition"
			;;
		btrfs)
			run_step "Formatting the root partition as btrfs" mkfs.btrfs -f "$root_partition"
			;;
		*)
			print_install_error "Unsupported filesystem: $filesystem"
			return 1
			;;
	esac
}

normalized_mount_source() {
	local mountpoint_path=${1:?mountpoint path is required}
	local mounted_source=""

	mounted_source="$(findmnt -n -o SOURCE "$mountpoint_path" 2>> "$ARCHINSTALL_LOG" || true)"
	printf '%s\n' "${mounted_source%%\[*}"
}

validate_target_mount() {
	local root_partition=${1:-}
	local expected_root_source=${2-}
	local mounted_source=""
	local mounted_fstype=""
	local normalized_source=""

	if [[ ! -d /mnt ]]; then
		print_install_error "Target mount point /mnt does not exist."
		return 1
	fi
	if ! mountpoint -q /mnt 2>> "$ARCHINSTALL_LOG"; then
		print_install_error "Target mount point /mnt is not an active mountpoint."
		return 1
	fi

	mounted_source="$(findmnt -n -o SOURCE /mnt 2>> "$ARCHINSTALL_LOG" || true)"
	mounted_fstype="$(findmnt -n -o FSTYPE /mnt 2>> "$ARCHINSTALL_LOG" || true)"
	if [[ -z $mounted_source ]]; then
		print_install_error "Target root filesystem is not mounted on /mnt."
		return 1
	fi
	if [[ $mounted_source == *airootfs* || $mounted_fstype == overlay || $mounted_fstype == squashfs ]]; then
		print_install_error "Target mount /mnt is pointing at the live environment instead of the install target."
		return 1
	fi

	normalized_source=${mounted_source%%\[*}
	if [[ -n $expected_root_source && $normalized_source != "$expected_root_source" ]]; then
		print_install_error "Target mount /mnt changed from expected source $expected_root_source to $mounted_source."
		return 1
	fi

	if [[ -n $root_partition && $normalized_source != "$root_partition" ]]; then
		print_install_error "Target mount /mnt does not match expected root partition $root_partition. Current source: $mounted_source"
		return 1
	fi

	return 0
}

verify_target_system_present() {
	validate_target_mount "$1" "$2" || return 1
	if [[ ! -f /mnt/etc/arch-release ]]; then
		print_install_error "Target system was not installed correctly: /mnt/etc/arch-release is missing."
		return 1
	fi
	return 0
}

verify_base_system_files() {
	validate_target_mount "$1" "$2" || return 1
	if [[ ! -f /mnt/etc/mkinitcpio.conf ]]; then
		print_install_error "Base system is incomplete: /mnt/etc/mkinitcpio.conf is missing."
		return 1
	fi
	if [[ ! -f /mnt/boot/vmlinuz-linux ]]; then
		print_install_error "Base system is incomplete: /mnt/boot/vmlinuz-linux is missing."
		return 1
	fi
	return 0
}

log_installed_target_packages() {
	validate_target_mount "$1" "$2" || return 1
	run_optional_step "Recording installed target packages" arch-chroot /mnt pacman -Q
	return 0
}

log_mount_state() {
	log_line "[DEBUG] Current mount state before chroot:"
	findmnt -R /mnt >> "$ARCHINSTALL_LOG" 2>&1 || true
}

prepare_chroot_mounts() {
	validate_target_mount "$1" "$2" || return 1
	run_step "Creating API filesystem mount points" mkdir -p /mnt/dev /mnt/proc /mnt/sys || return 1
	if ! mountpoint -q /mnt/dev 2>> "$ARCHINSTALL_LOG"; then
		run_step "Bind mounting /dev into target" mount --bind /dev /mnt/dev || return 1
	fi
	if ! mountpoint -q /mnt/proc 2>> "$ARCHINSTALL_LOG"; then
		run_step "Bind mounting /proc into target" mount --bind /proc /mnt/proc || return 1
	fi
	if ! mountpoint -q /mnt/sys 2>> "$ARCHINSTALL_LOG"; then
		run_step "Bind mounting /sys into target" mount --bind /sys /mnt/sys || return 1
	fi
	validate_target_mount "$1" "$2" || return 1
	log_mount_state
	return 0
}

mount_root_filesystem() {
	local filesystem=${1:?filesystem is required}
	local disk_type=${2:?disk type is required}
	local root_partition=${3:?root partition is required}
	local root_mount_options=""
	local home_mount_options=""

	run_step "Creating the target mount point" mkdir -p /mnt || return 1

	case $filesystem in
		ext4)
			root_mount_options="$(ext4_mount_options "$disk_type")"
			run_step "Mounting the root filesystem" mount -o "$root_mount_options" "$root_partition" /mnt
			;;
		btrfs)
			run_step "Mounting btrfs volume for subvolume creation" mount "$root_partition" /mnt || return 1
			if [[ ! -d /mnt/@ ]]; then
				run_step "Creating btrfs root subvolume" btrfs subvolume create /mnt/@ || return 1
			else
				log_line "[ OK ] Reusing existing btrfs root subvolume @"
			fi
			if [[ ! -d /mnt/@home ]]; then
				run_step "Creating btrfs home subvolume" btrfs subvolume create /mnt/@home || return 1
			else
				log_line "[ OK ] Reusing existing btrfs home subvolume @home"
			fi
			if [[ ! -d /mnt/@var ]]; then
				run_step "Creating btrfs var subvolume" btrfs subvolume create /mnt/@var || return 1
			else
				log_line "[ OK ] Reusing existing btrfs var subvolume @var"
			fi
			if [[ ! -d /mnt/@snapshots ]]; then
				run_step "Creating btrfs snapshots subvolume" btrfs subvolume create /mnt/@snapshots || return 1
			else
				log_line "[ OK ] Reusing existing btrfs snapshots subvolume @snapshots"
			fi
			log_line "[DEBUG] Unmounting temporary top-level btrfs mount before remounting subvolumes"
			run_step "Unmounting temporary btrfs mount" umount /mnt || return 1
			root_mount_options="$(btrfs_mount_options '@' "$disk_type")"
			home_mount_options="$(btrfs_mount_options '@home' "$disk_type")"
			run_step "Mounting the btrfs root subvolume" mount -o "$root_mount_options" "$root_partition" /mnt || return 1
			run_step "Creating the home mount point" mkdir -p /mnt/home || return 1
			run_step "Mounting the btrfs home subvolume" mount -o "$home_mount_options" "$root_partition" /mnt/home || return 1
			var_mount_options="$(btrfs_mount_options '@var' "$disk_type")"
			snapshots_mount_options="$(btrfs_mount_options '@snapshots' "$disk_type")"
			run_step "Creating the var mount point" mkdir -p /mnt/var || return 1
			run_step "Mounting the btrfs var subvolume" mount -o "$var_mount_options" "$root_partition" /mnt/var || return 1
			run_step "Creating the snapshots mount point" mkdir -p /mnt/.snapshots || return 1
			run_step "Mounting the btrfs snapshots subvolume" mount -o "$snapshots_mount_options" "$root_partition" /mnt/.snapshots || return 1
			run_optional_step "Recording mounted btrfs root subvolume" findmnt -no TARGET,SOURCE,OPTIONS /mnt
			run_optional_step "Recording mounted btrfs home subvolume" findmnt -no TARGET,SOURCE,OPTIONS /mnt/home
			run_optional_step "Recording mounted btrfs var subvolume" findmnt -no TARGET,SOURCE,OPTIONS /mnt/var
			run_optional_step "Recording mounted btrfs snapshots subvolume" findmnt -no TARGET,SOURCE,OPTIONS /mnt/.snapshots
			;;
		*)
			print_install_error "Unsupported filesystem: $filesystem"
			return 1
			;;
	esac
}

resolve_target_partitions() {
	local disk=${1:?disk is required}
	local boot_mode=${2:?boot mode is required}
	local efi_partition=""
	local root_partition=""

	efi_partition="$(get_state "EFI_PART" 2>/dev/null || true)"
	root_partition="$(get_state "ROOT_PART" 2>/dev/null || true)"

	if [[ $boot_mode == "uefi" ]]; then
		[[ -n $efi_partition ]] || efi_partition="$(disk_partition_path "$disk" 1)"
		[[ -n $root_partition ]] || root_partition="$(disk_partition_path "$disk" 2)"
	else
		efi_partition="-"
		[[ -n $root_partition ]] || root_partition="$(disk_partition_path "$disk" 1)"
	fi

	if [[ $boot_mode == "uefi" && ! -b $efi_partition ]]; then
		print_install_error "Expected EFI partition was not found: $efi_partition"
		return 1
	fi

	if [[ ! -b $root_partition ]]; then
		print_install_error "Expected partitions were not found: $efi_partition $root_partition"
		return 1
	fi

	printf '%s\n%s\n' "$efi_partition" "$root_partition"
}

build_chroot_script() {
	local boot_mode=${1:?boot mode is required}
	local disk=${2:?disk is required}
	local root_uuid=${3:?root UUID is required}
	local filesystem=${4:?filesystem is required}
	local root_mount_options=${5:-}
	local enable_zram=${6:?zram flag is required}
	local desktop_profile=${7:-none}
	local display_manager=${8:-none}
	local display_mode=${9:-auto}
	local resolved_display_mode=${10:-wayland}
	local greeter_frontend=""
	local hostname=""
	local timezone=""
	local locale=""
	local keymap=""
	local username=""
	local user_password=${INSTALL_USER_PASSWORD:-}
	local root_password=${INSTALL_ROOT_PASSWORD:-}
	local quoted_boot_mode=""
	local quoted_disk=""
	local quoted_root_uuid=""
	local quoted_hostname=""
	local quoted_timezone=""
	local quoted_locale=""
	local quoted_keymap=""
	local quoted_username=""
	local quoted_user_password=""
	local quoted_root_password=""
	local quoted_filesystem=""
	local quoted_root_mount_options=""
	local quoted_enable_zram=""
	local quoted_desktop_profile=""
	local quoted_display_manager=""
	local quoted_greeter_frontend=""
	local quoted_display_mode=""
	local quoted_resolved_display_mode=""
	local install_profile=""
	local editor_choice=""
	local include_vscode=""
	local custom_tools=""
	local secure_boot_mode=""
	local current_secure_boot_state=""
	local current_secure_boot_setup_mode=""
	local environment_vendor=""
	local gpu_vendor=""
	local snapshot_provider=""
	local enable_luks=""
	local luks_mapper_name=""
	local luks_partition_uuid=""
	local mkinitcpio_hooks=""
	local quoted_install_profile=""
	local quoted_editor_choice=""
	local quoted_include_vscode=""
	local quoted_custom_tools=""
	local quoted_secure_boot_mode=""
	local quoted_current_secure_boot_state=""
	local quoted_current_secure_boot_setup_mode=""
	local quoted_environment_vendor=""
	local quoted_gpu_vendor=""
	local quoted_snapshot_provider=""
	local quoted_enable_luks=""
	local quoted_luks_mapper_name=""
	local quoted_luks_partition_uuid=""
	local quoted_mkinitcpio_hooks=""

	hostname="$(get_state "HOSTNAME" 2>/dev/null || printf 'archlinux')"
	timezone="$(get_state "TIMEZONE" 2>/dev/null || printf 'Europe/Istanbul')"
	locale="$(get_state "LOCALE" 2>/dev/null || printf 'en_US.UTF-8')"
	keymap="$(get_state "KEYMAP" 2>/dev/null || printf 'us')"
	username="$(get_state "USERNAME" 2>/dev/null || printf 'archuser')"
	install_profile="$(get_state "INSTALL_PROFILE" 2>/dev/null || printf 'daily')"
	editor_choice="$(get_state "EDITOR_CHOICE" 2>/dev/null || printf 'nano')"
	include_vscode="$(get_state "INCLUDE_VSCODE" 2>/dev/null || printf 'false')"
	custom_tools="$(get_state "CUSTOM_TOOLS" 2>/dev/null || printf '')"
	secure_boot_mode="$(get_state "SECURE_BOOT_MODE" 2>/dev/null || printf 'disabled')"
	current_secure_boot_state="$(get_state "CURRENT_SECURE_BOOT_STATE" 2>/dev/null || printf 'unsupported')"
	current_secure_boot_setup_mode="$(get_state "CURRENT_SECURE_BOOT_SETUP_MODE" 2>/dev/null || printf 'unknown')"
	environment_vendor="$(get_state "ENVIRONMENT_VENDOR" 2>/dev/null || printf 'baremetal')"
	local environment_type=""
	environment_type="$(get_state "ENVIRONMENT_TYPE" 2>/dev/null || printf 'unknown')"
	gpu_vendor="$(get_state "GPU_VENDOR" 2>/dev/null || printf 'generic')"
	snapshot_provider="$(get_state "SNAPSHOT_PROVIDER" 2>/dev/null || printf 'none')"
	enable_luks="$(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false')"
	luks_mapper_name="$(get_state "LUKS_MAPPER_NAME" 2>/dev/null || printf 'cryptroot')"
	luks_partition_uuid="$(get_state "LUKS_PART_UUID" 2>/dev/null || printf '')"
	mkinitcpio_hooks="$(luks_mkinitcpio_hooks 2>/dev/null || printf 'base udev autodetect modconf block filesystems keyboard fsck')"
	greeter_frontend="$(get_state "GREETER_FRONTEND" 2>/dev/null || printf 'tuigreet')"

	if [[ -z $user_password ]]; then
		print_install_error "The installer user password is not set. Configure the install profile before starting."
		return 1
	fi
	if [[ -z $root_password ]]; then
		print_install_error "The root password is not set. Configure the install profile before starting."
		return 1
	fi

	printf -v quoted_boot_mode '%q' "$boot_mode"
	printf -v quoted_disk '%q' "$disk"
	printf -v quoted_root_uuid '%q' "$root_uuid"
	printf -v quoted_hostname '%q' "$hostname"
	printf -v quoted_timezone '%q' "$timezone"
	printf -v quoted_locale '%q' "$locale"
	printf -v quoted_keymap '%q' "$keymap"
	printf -v quoted_username '%q' "$username"
	printf -v quoted_user_password '%q' "$user_password"
	printf -v quoted_root_password '%q' "$root_password"
	printf -v quoted_filesystem '%q' "$filesystem"
	printf -v quoted_root_mount_options '%q' "$root_mount_options"
	printf -v quoted_enable_zram '%q' "$enable_zram"
	printf -v quoted_desktop_profile '%q' "$desktop_profile"
	printf -v quoted_display_manager '%q' "$display_manager"
	printf -v quoted_greeter_frontend '%q' "$greeter_frontend"
	printf -v quoted_display_mode '%q' "$display_mode"
	printf -v quoted_resolved_display_mode '%q' "$resolved_display_mode"
	printf -v quoted_install_profile '%q' "$install_profile"
	printf -v quoted_editor_choice '%q' "$editor_choice"
	printf -v quoted_include_vscode '%q' "$include_vscode"
	printf -v quoted_custom_tools '%q' "$custom_tools"
	printf -v quoted_secure_boot_mode '%q' "$secure_boot_mode"
	printf -v quoted_current_secure_boot_state '%q' "$current_secure_boot_state"
	printf -v quoted_current_secure_boot_setup_mode '%q' "$current_secure_boot_setup_mode"
	printf -v quoted_environment_vendor '%q' "$environment_vendor"
	local quoted_environment_type=""
	printf -v quoted_environment_type '%q' "$environment_type"
	printf -v quoted_gpu_vendor '%q' "$gpu_vendor"
	printf -v quoted_snapshot_provider '%q' "$snapshot_provider"
	printf -v quoted_enable_luks '%q' "$enable_luks"
	printf -v quoted_luks_mapper_name '%q' "$luks_mapper_name"
	printf -v quoted_luks_partition_uuid '%q' "$luks_partition_uuid"
	printf -v quoted_mkinitcpio_hooks '%q' "$mkinitcpio_hooks"

	cat <<EOF
set -euo pipefail

BOOT_MODE=$quoted_boot_mode
TARGET_DISK=$quoted_disk
ROOT_UUID=$quoted_root_uuid
TARGET_HOSTNAME=$quoted_hostname
TARGET_TIMEZONE=$quoted_timezone
TARGET_LOCALE=$quoted_locale
TARGET_KEYMAP=$quoted_keymap
TARGET_USERNAME=$quoted_username
TARGET_USER_PASSWORD=$quoted_user_password
TARGET_ROOT_PASSWORD=$quoted_root_password
TARGET_FILESYSTEM=$quoted_filesystem
TARGET_ROOT_MOUNT_OPTIONS=$quoted_root_mount_options
TARGET_ENABLE_ZRAM=$quoted_enable_zram
TARGET_DESKTOP_PROFILE=$quoted_desktop_profile
TARGET_DISPLAY_MANAGER=$quoted_display_manager
TARGET_GREETER_FRONTEND=$quoted_greeter_frontend
TARGET_DISPLAY_MODE=$quoted_display_mode
TARGET_RESOLVED_DISPLAY_MODE=$quoted_resolved_display_mode
TARGET_INSTALL_PROFILE=$quoted_install_profile
TARGET_EDITOR_CHOICE=$quoted_editor_choice
TARGET_INCLUDE_VSCODE=$quoted_include_vscode
TARGET_CUSTOM_TOOLS=$quoted_custom_tools
TARGET_SECURE_BOOT_MODE=$quoted_secure_boot_mode
TARGET_CURRENT_SECURE_BOOT_STATE=$quoted_current_secure_boot_state
TARGET_SECURE_BOOT_SETUP_MODE=$quoted_current_secure_boot_setup_mode
TARGET_ENVIRONMENT_VENDOR=$quoted_environment_vendor
TARGET_ENVIRONMENT_TYPE=$quoted_environment_type
TARGET_GPU_VENDOR=$quoted_gpu_vendor
TARGET_SNAPSHOT_PROVIDER=$quoted_snapshot_provider
TARGET_LUKS_ENABLED=$quoted_enable_luks
TARGET_LUKS_MAPPER_NAME=$quoted_luks_mapper_name
LUKS_UUID=$quoted_luks_partition_uuid
TARGET_MKINITCPIO_HOOKS=$quoted_mkinitcpio_hooks
export PACMAN_OPTS='${PACMAN_OPTS:---noconfirm --needed}'

log_chroot_step() {
	echo "[STEP] $1"
}

log_chroot_step "Configuring mkinitcpio hooks"
if [[ ! -f /etc/mkinitcpio.conf ]]; then
	echo "[FAIL] /etc/mkinitcpio.conf is missing inside the target chroot"
	exit 1
fi
echo "[DEBUG] Preparing to update /etc/mkinitcpio.conf inside chroot"
echo "[DEBUG] Applying mkinitcpio hooks"
sed -i "s/^HOOKS=.*/HOOKS=(\$TARGET_MKINITCPIO_HOOKS)/" /etc/mkinitcpio.conf

log_chroot_step "Configuring timezone"
ln -sf "/usr/share/zoneinfo/\$TARGET_TIMEZONE" /etc/localtime
hwclock --systohc

log_chroot_step "Configuring locale"
if ! grep -qx "\$TARGET_LOCALE UTF-8" /etc/locale.gen; then
	echo "\$TARGET_LOCALE UTF-8" >> /etc/locale.gen
fi
locale-gen
printf '%s\n' "LANG=\$TARGET_LOCALE" > /etc/locale.conf
printf '%s\n' "KEYMAP=\$TARGET_KEYMAP" > /etc/vconsole.conf

log_chroot_step "Configuring hostname and hosts"
printf '%s\n' "\$TARGET_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<'EOT'
127.0.0.1 localhost
::1       localhost
127.0.1.1 TARGET_HOSTNAME.localdomain TARGET_HOSTNAME
EOT
sed -i "s/TARGET_HOSTNAME/\$TARGET_HOSTNAME/g" /etc/hosts

log_chroot_step "Creating user accounts and setting passwords"
if ! id -u "\$TARGET_USERNAME" >/dev/null 2>&1; then
	useradd -m -G wheel -s /bin/bash "\$TARGET_USERNAME"
fi
echo "\$TARGET_USERNAME:\$TARGET_USER_PASSWORD" | chpasswd
echo "root:\$TARGET_ROOT_PASSWORD" | chpasswd

log_chroot_step "Configuring sudo permissions"
if grep -q '^# %wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
	sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
elif ! grep -q '^%wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
	echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
fi

log_chroot_step "Enabling NetworkManager"
systemctl enable NetworkManager

# When iwd is installed, use it as the Wi-Fi backend for NetworkManager.
# This provides better security and WPA3 support over wpa_supplicant.
if command -v iwctl >/dev/null 2>&1; then
	log_chroot_step "Configuring iwd as NetworkManager Wi-Fi backend"
	install -d -m 755 /etc/NetworkManager/conf.d
	cat > /etc/NetworkManager/conf.d/wifi_backend.conf <<'NMCONFIGEOF'
[device]
wifi.backend=iwd
NMCONFIGEOF
	systemctl enable iwd.service
fi

enable_service_if_present() {
	local service_name=
	service_name=\${1:?service name is required}
	if systemctl list-unit-files "\$service_name" >/dev/null 2>&1; then
		systemctl enable "\$service_name" || true
	else
		echo "[WARN] Optional service not present: \$service_name"
	fi
}

write_secure_boot_notice() {
	install -d -m 0700 /root
	cat > /root/ARCHINSTALL_SECURE_BOOT.txt <<EOT
Secure Boot firmware state: \$TARGET_CURRENT_SECURE_BOOT_STATE
Secure Boot mode: \$TARGET_SECURE_BOOT_MODE
Firmware setup mode: \$TARGET_SECURE_BOOT_SETUP_MODE
Install profile: \$TARGET_INSTALL_PROFILE
Environment: \$TARGET_ENVIRONMENT_VENDOR
GPU: \$TARGET_GPU_VENDOR

This installer uses mkinitcpio + ukify to build a Unified Kernel Image when Secure Boot mode is enabled.
It keeps the workflow non-fatal: VM firmware quirks, missing tooling, or signing failures will not abort the install.

If the GPU is NVIDIA, the installer enables early driver modules and appends nvidia_drm.modeset=1 to the kernel command line.
If the environment is virtualized, automatic key enrollment is skipped unless you handle firmware ownership manually.

Recommended follow-up commands:
  sbctl status
  sbctl create-keys
  sbctl enroll-keys -m
  sbctl verify
EOT
}

build_kernel_cmdline() {
	local kernel_cmdline=""

	if [[ \$TARGET_LUKS_ENABLED == "true" && -n \${LUKS_UUID:-} ]]; then
		kernel_cmdline="cryptdevice=UUID=\$LUKS_UUID:\$TARGET_LUKS_MAPPER_NAME root=UUID=\$ROOT_UUID rw"
	else
		kernel_cmdline="root=UUID=\$ROOT_UUID rw"
	fi

	if [[ \$TARGET_FILESYSTEM == "btrfs" ]]; then
		kernel_cmdline="\$kernel_cmdline rootfstype=btrfs rootflags=\$TARGET_ROOT_MOUNT_OPTIONS"
	fi
	if [[ \$TARGET_GPU_VENDOR == "nvidia" ]]; then
		kernel_cmdline="\$kernel_cmdline nvidia_drm.modeset=1"
	fi

	printf '%s\n' "\$kernel_cmdline"
}

configure_nvidia_mkinitcpio() {
	if [[ \$TARGET_GPU_VENDOR != "nvidia" ]]; then
		return 0
	fi

	if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
		sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
	else
		echo 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' >> /etc/mkinitcpio.conf
	fi
}

write_uki_configuration() {
	local kernel_cmdline=""

	install -d -m 0755 /etc/kernel /boot/EFI/Linux
	kernel_cmdline="\$(build_kernel_cmdline)"
	printf '%s\n' "\$kernel_cmdline" > /etc/kernel/cmdline
	cat > /etc/mkinitcpio.d/linux.preset <<'EOT'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux.efi"
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
EOT
}

sign_efi_binary_if_present() {
	local binary_path=
	binary_path=\${1:-}
	[[ -n \$binary_path ]] || return 0
	[[ -e \$binary_path ]] || return 0

	if ! sbctl sign -s "\$binary_path"; then
		echo "[WARN] sbctl could not sign \$binary_path"
		return 1
	fi
	return 0
}

configure_vm_services() {
	case \$TARGET_ENVIRONMENT_VENDOR in
		vmware)
			enable_service_if_present vmtoolsd.service
			;;
		virtualbox)
			enable_service_if_present vboxservice.service
			;;
		kvm|qemu)
			enable_service_if_present spice-vdagentd.service
			enable_service_if_present qemu-guest-agent.service
			;;
		hyperv)
			enable_service_if_present hv_fcopy_daemon.service
			enable_service_if_present hv_kvp_daemon.service
			enable_service_if_present hv_vss_daemon.service
			;;
		*)
			;;
	esac
	if [[ \$TARGET_ENVIRONMENT_TYPE == "laptop" ]]; then
		enable_service_if_present tlp.service
		enable_service_if_present acpid.service
	fi
}

configure_secure_boot_mode() {
	if [[ \$BOOT_MODE != "uefi" ]]; then
		return 0
	fi

	case \$TARGET_SECURE_BOOT_MODE in
		disabled)
			return 0
			;;
		assisted|advanced)
			log_chroot_step "Preparing Secure Boot and UKI tooling"
			if ! command -v sbctl >/dev/null 2>&1; then
				echo "[WARN] sbctl is not installed in the target system."
				mkinitcpio -P || true
				write_secure_boot_notice
				return 0
			fi
			if ! command -v ukify >/dev/null 2>&1; then
				echo "[WARN] ukify is not installed in the target system. Falling back to the standard initramfs path."
				mkinitcpio -P || true
				write_secure_boot_notice
				return 0
			fi
			configure_nvidia_mkinitcpio
			write_uki_configuration
			sbctl status || true
			if [[ ! -d /var/lib/sbctl/keys ]]; then
				sbctl create-keys || true
			fi
			if [[ \$TARGET_SECURE_BOOT_MODE == "assisted" && \$TARGET_SECURE_BOOT_SETUP_MODE == "setup" && \$TARGET_ENVIRONMENT_VENDOR == "baremetal" ]]; then
				sbctl enroll-keys -m || true
			elif [[ \$TARGET_SECURE_BOOT_MODE == "assisted" && \$TARGET_ENVIRONMENT_VENDOR != "baremetal" ]]; then
				echo "[WARN] Virtualized environment detected. Skipping automatic key enrollment."
			fi
			mkinitcpio -P || {
				echo "[WARN] mkinitcpio failed to build UKIs. Continuing with the rest of the install."
				write_secure_boot_notice
				return 0
			}
			sign_efi_binary_if_present /boot/EFI/Linux/arch-linux.efi || true
			sign_efi_binary_if_present /boot/EFI/Linux/arch-linux-fallback.efi || true
			sign_efi_binary_if_present /boot/EFI/systemd/systemd-bootx64.efi || true
			sign_efi_binary_if_present /boot/EFI/BOOT/BOOTX64.EFI || true
			write_secure_boot_notice
			;;
		*)
			;;
	esac
}

if [[ \$TARGET_ENABLE_ZRAM == "true" ]]; then
	log_chroot_step "Configuring zram"
	mkdir -p /etc/systemd
	cat > /etc/systemd/zram-generator.conf <<'EOT'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOT
fi

$(snapshot_chroot_setup_snippet "$(get_state "SNAPSHOT_PROVIDER" 2>/dev/null || printf 'none')" "$filesystem")

write_display_manager_fallback_notice() {
	local fallback_command=\${1:-startplasma-wayland}
	install -d -m 0755 /etc/profile.d
	cat > /etc/profile.d/archinstall-desktop-fallback.sh <<EOT
if [[ -z "\${DISPLAY:-}" && -z "\${WAYLAND_DISPLAY:-}" && "\$(tty 2>/dev/null || true)" == /dev/tty* ]]; then
	echo "Display manager failed, start KDE manually with: \$fallback_command"
fi
EOT
}

write_x11_fallback_helper() {
	install -d -m 0755 /usr/local/bin
	cat > /usr/local/bin/archinstall-startplasma-x11 <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
printf 'exec startplasma-x11\n' > "$HOME/.xinitrc"
exec startx
EOT
	chmod 0755 /usr/local/bin/archinstall-startplasma-x11
}

plasma_session_command() {
	case \${1:-wayland} in
		x11)
			printf 'startplasma-x11\n'
			;;
		*)
			printf 'startplasma-wayland\n'
			;;
	esac
}

PLASMA_SESSION_COMMAND="\$(plasma_session_command "\$TARGET_RESOLVED_DISPLAY_MODE")"
PLASMA_GREETD_COMMAND="startplasma-wayland"

write_x11_fallback_helper

build_greetd_command() {
	case \${1:-tuigreet} in
		qtgreet)
			printf 'qtgreet\n'
			;;
		*)
			printf 'tuigreet --remember --remember-session --sessions /usr/share/wayland-sessions --cmd %s\n' "\$PLASMA_GREETD_COMMAND"
			;;
	esac
}

if [[ \$TARGET_SECURE_BOOT_MODE == "disabled" || \$BOOT_MODE != "uefi" ]]; then
	log_chroot_step "Rebuilding initramfs"
	mkinitcpio -P
fi

if [[ \$TARGET_DESKTOP_PROFILE == "kde" ]]; then
	log_chroot_step "Configuring KDE services"
	enable_service_if_present bluetooth.service
	install -d -m 0755 /etc/systemd/user/default.target.wants
	ln -sf /usr/lib/systemd/user/pipewire.service /etc/systemd/user/default.target.wants/pipewire.service
	ln -sf /usr/lib/systemd/user/pipewire-pulse.service /etc/systemd/user/default.target.wants/pipewire-pulse.service
	ln -sf /usr/lib/systemd/user/wireplumber.service /etc/systemd/user/default.target.wants/wireplumber.service

	# Disable all known display managers before enabling the selected one.
	# This prevents conflicts if the user re-runs install or changes DM selection.
	log_chroot_step "Disabling any previously enabled display managers"
	for _dm_svc in sddm.service greetd.service lightdm.service gdm.service lxdm.service; do
		systemctl disable "\$_dm_svc" 2>/dev/null || true
	done

	case \$TARGET_DISPLAY_MANAGER in
		greetd)
			log_chroot_step "Configuring greetd"
			if [[ \$TARGET_GREETER_FRONTEND == "qtgreet" ]] && ! command -v qtgreet >/dev/null 2>&1; then
				echo "[WARN] qtgreet was selected but is not installed. Falling back to tuigreet if available."
				TARGET_GREETER_FRONTEND="tuigreet"
			fi
			if [[ \$TARGET_GREETER_FRONTEND == "qtgreet" ]] && command -v qtgreet >/dev/null 2>&1; then
				install -d -m 0755 /etc/greetd
				cat > /etc/greetd/config.toml <<EOT
[terminal]
vt = 1

[default_session]
command = "\$(build_greetd_command qtgreet)"
user = "greeter"
EOT
				systemctl enable greetd.service
				write_display_manager_fallback_notice "archinstall-startplasma-x11"
			elif command -v tuigreet >/dev/null 2>&1; then
				install -d -m 0755 /etc/greetd
				cat > /etc/greetd/config.toml <<EOT
[terminal]
vt = 1

[default_session]
command = "\$(build_greetd_command tuigreet)"
user = "greeter"
EOT
				systemctl enable greetd.service
				write_display_manager_fallback_notice "archinstall-startplasma-x11"
			else
				echo "[WARN] No supported greetd frontend is installed in the target system. Leaving the system on TTY."
				write_display_manager_fallback_notice "archinstall-startplasma-x11"
			fi
			;;
		sddm)
			log_chroot_step "Configuring SDDM"
			if command -v sddm >/dev/null 2>&1; then
				# Create SDDM configuration directory and set a sane default theme
				install -d -m 0755 /etc/sddm.conf.d
				cat > /etc/sddm.conf.d/kde_settings.conf <<'SDDMCONF'
[Autologin]
Relogin=false
Session=
User=

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[Theme]
Current=breeze

[Users]
MaximumUid=60000
MinimumUid=1000
SDDMCONF
				systemctl enable sddm.service
				write_display_manager_fallback_notice "\$PLASMA_SESSION_COMMAND"
			else
				echo "[WARN] sddm binary not found in target system. Skipping SDDM configuration."
				write_display_manager_fallback_notice "archinstall-startplasma-x11"
			fi
			;;
		*)
			write_display_manager_fallback_notice "archinstall-startplasma-x11"
			;;
	esac
fi

if type emit_chroot_snippets >/dev/null 2>&1; then
	emit_chroot_snippets
fi

configure_vm_services
enable_service_if_present bluetooth.service

if [[ \$BOOT_MODE == "uefi" ]]; then
	log_chroot_step "Installing systemd-boot"
	bootctl install
	mkdir -p /boot/loader/entries

	# Detect installed microcode image for early CPU microcode loading
	MICROCODE_INITRD_LINE=""
	if [[ -f /boot/intel-ucode.img ]]; then
		MICROCODE_INITRD_LINE="initrd /intel-ucode.img"
	elif [[ -f /boot/amd-ucode.img ]]; then
		MICROCODE_INITRD_LINE="initrd /amd-ucode.img"
	fi

	# Write loader.conf. For Secure Boot mode, use @saved so sd-boot defaults to
	# the last successfully booted entry (the signed UKI from /boot/EFI/Linux/).
	if [[ \$TARGET_SECURE_BOOT_MODE == "disabled" ]]; then
		cat > /boot/loader/loader.conf <<'LOADERCONF'
default arch
timeout 3
editor no
LOADERCONF
	else
		cat > /boot/loader/loader.conf <<'LOADERCONF'
default @saved
timeout 3
editor no
LOADERCONF
	fi

	# Always write arch.conf. This is the permanent unsigned fallback entry.
	# Removing it would leave no viable boot path if UKI signing or enrollment fails.
	# When Secure Boot is active, sd-boot auto-discovers signed UKIs from /boot/EFI/Linux/
	# and they take default priority via @saved; arch.conf stays selectable manually.
	{
		echo "title Arch Linux"
		echo "linux /vmlinuz-linux"
		[[ -n "\$MICROCODE_INITRD_LINE" ]] && echo "\$MICROCODE_INITRD_LINE"
		echo "initrd /initramfs-linux.img"
		echo "options \$(build_kernel_cmdline)"
	} > /boot/loader/entries/arch.conf

	echo "[DEBUG] systemd-boot arch.conf:"
	cat /boot/loader/entries/arch.conf
else
	log_chroot_step "Installing GRUB"

	# BIOS+GPT safety guard: grub-install --target=i386-pc cannot embed on a GPT
	# disk unless a dedicated 1 MiB bios_grub partition exists.
	if [[ \$BOOT_MODE == "bios" ]]; then
		GRUB_DISK_LABEL="\$(parted -s "\$TARGET_DISK" print 2>/dev/null | awk '/Partition Table:/ {print \$3}' || true)"
		if [[ "\$GRUB_DISK_LABEL" == "gpt" ]]; then
			if ! parted -s "\$TARGET_DISK" print 2>/dev/null | grep -qi 'bios_grub'; then
				echo "[FAIL] BIOS install on GPT disk requires a bios_grub partition. None found on \$TARGET_DISK."
				echo "[FAIL] Create a 1 MiB unformatted partition with the bios_grub flag and retry."
				exit 1
			fi
			echo "[INFO] bios_grub partition confirmed on GPT disk - proceeding with GRUB embed."
		fi
	fi

	grub_cmdline="root=UUID=\$ROOT_UUID"
	if [[ \$TARGET_FILESYSTEM == "btrfs" ]]; then
		grub_cmdline="\$grub_cmdline rootfstype=btrfs rootflags=\$TARGET_ROOT_MOUNT_OPTIONS"
	fi
	if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
		sed -i "s#^GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX=\"\$grub_cmdline\"#" /etc/default/grub
	else
		printf '%s\n' "GRUB_CMDLINE_LINUX=\"\$grub_cmdline\"" >> /etc/default/grub
	fi
	if grep -q '^GRUB_DISABLE_LINUX_UUID=' /etc/default/grub; then
		sed -i 's/^GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
	else
		echo 'GRUB_DISABLE_LINUX_UUID=true' >> /etc/default/grub
	fi

	grub-install --target=i386-pc "\$TARGET_DISK"
	grub-mkconfig -o /boot/grub/grub.cfg

	echo "[DEBUG] /etc/default/grub"
	cat /etc/default/grub
	echo "[DEBUG] Generated grub.cfg linux lines"
	grep -n 'linux.*/vmlinuz-linux' /boot/grub/grub.cfg || true
fi

configure_secure_boot_mode
EOF
}

run_chroot_configuration() {
	local boot_mode=${1:?boot mode is required}
	local disk=${2:?disk is required}
	local root_uuid=${3:?root UUID is required}
	local filesystem=${4:?filesystem is required}
	local root_mount_options=${5:-}
	local enable_zram=${6:?zram flag is required}
	local desktop_profile=${7:-none}
	local display_manager=${8:-none}
	local display_mode=${9:-auto}
	local resolved_display_mode=${10:-wayland}
	local root_partition=${11:-}
	local expected_root_source=${12:-}

	install_ui_uses_dialog || print_install_info "Configuring the new system and installing the bootloader"
	log_line "[STEP] Configuring the target system inside chroot"
	validate_target_mount "$root_partition" "$expected_root_source" || return 1
	if [[ ! -f /mnt/etc/arch-release ]]; then
		print_install_error "Refusing to chroot because /mnt/etc/arch-release is missing."
		return 1
	fi
	log_line "[DEBUG] Mount state immediately before arch-chroot"
	log_mount_state

	if install_ui_uses_dialog; then
		if build_chroot_script "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$root_mount_options" "$enable_zram" "$desktop_profile" "$display_manager" "$display_mode" "$resolved_display_mode" | arch-chroot /mnt /bin/bash -s 2>&1 | sanitize_stream | tee_install_logs >/dev/null
		then
			log_line "[ OK ] Configuring the target system inside chroot"
			return 0
		fi
	else
		if build_chroot_script "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$root_mount_options" "$enable_zram" "$desktop_profile" "$display_manager" "$display_mode" "$resolved_display_mode" | arch-chroot /mnt /bin/bash -s 2>&1 | sanitize_stream | tee_install_logs
		then
			log_line "[ OK ] Configuring the target system inside chroot"
			return 0
		fi
	fi

	log_line "[FAIL] Configuring the target system inside chroot"
	show_install_error "Configuring the new system"
	return 1
}

run_install() {
	local disk=""
	local efi_partition=""
	local root_partition=""
	local root_mount_device=""
	local root_uuid=""
	local luks_partition_uuid=""
	local boot_mode=""
	local disk_type=""
	local filesystem=""
	local enable_zram=""
	local install_profile=""
	local editor_choice=""
	local include_vscode="false"
	local custom_tools=""
	local secure_boot_mode="disabled"
	local current_secure_boot_state="unsupported"
	local environment_vendor="baremetal"
	local gpu_vendor="generic"
	local install_scenario="wipe"
	local format_root="true"
	local format_efi="true"
	local desktop_profile=""
	local display_manager=""
	local greeter_frontend="tuigreet"
	local display_mode=""
	local resolved_display_mode=""
	local enable_luks="false"
	local luks_mapper_name="cryptroot"
	local snapshot_provider="none"
	local required_space_mib=""
	local root_mount_options=""
	local expected_root_source=""
	local install_status=0
	local -a resolved_partitions=()
	local -a pacstrap_packages=()

	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		print_install_error "Run the installer as root from the Arch Linux live environment."
		return 1
	fi

	require_commands || return 1

	disk="$(get_state "DISK" 2>/dev/null || true)"
	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || true)"
	filesystem="$(normalize_filesystem "$(get_state "FILESYSTEM" 2>/dev/null || printf 'ext4')")"
	enable_zram="$(get_state "ENABLE_ZRAM" 2>/dev/null || printf 'false')"
	install_profile="$(get_state "INSTALL_PROFILE" 2>/dev/null || printf 'daily')"
	editor_choice="$(get_state "EDITOR_CHOICE" 2>/dev/null || printf 'nano')"
	include_vscode="$(get_state "INCLUDE_VSCODE" 2>/dev/null || printf 'false')"
	custom_tools="$(get_state "CUSTOM_TOOLS" 2>/dev/null || printf '')"
	secure_boot_mode="$(get_state "SECURE_BOOT_MODE" 2>/dev/null || printf 'disabled')"
	install_scenario="$(get_state "INSTALL_SCENARIO" 2>/dev/null || printf 'wipe')"
	format_root="$(get_state "FORMAT_ROOT" 2>/dev/null || printf 'true')"
	format_efi="$(get_state "FORMAT_EFI" 2>/dev/null || printf 'true')"
	desktop_profile="$(get_state "DESKTOP_PROFILE" 2>/dev/null || printf 'none')"
	display_manager="$(get_state "DISPLAY_MANAGER" 2>/dev/null || printf 'none')"
	greeter_frontend="$(get_state "GREETER_FRONTEND" 2>/dev/null || printf 'tuigreet')"
	display_mode="$(get_state "DISPLAY_MODE" 2>/dev/null || printf 'auto')"
	enable_luks="$(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false')"
	luks_mapper_name="$(get_state "LUKS_MAPPER_NAME" 2>/dev/null || printf 'cryptroot')"
	snapshot_provider="$(get_state "SNAPSHOT_PROVIDER" 2>/dev/null || printf 'none')"
	[[ -n $boot_mode ]] || boot_mode="$(detect_boot_mode)"
	current_secure_boot_state="$(detect_secure_boot_state "$boot_mode")"
	environment_vendor="$(detect_virtualization_vendor)"
	gpu_vendor="$(detect_gpu_vendor)"
	local cpu_vendor
	cpu_vendor="$(detect_cpu_vendor_safe 2>/dev/null || printf 'unknown')"
	set_state "CURRENT_SECURE_BOOT_STATE" "$current_secure_boot_state" || return 1
	set_state "CURRENT_SECURE_BOOT_SETUP_MODE" "$(detect_secure_boot_setup_mode "$boot_mode")" || return 1
	set_state "ENVIRONMENT_VENDOR" "$environment_vendor" || return 1
	set_state "ENVIRONMENT_LABEL" "$(environment_label "$environment_vendor")" || return 1
	set_state "GPU_VENDOR" "$gpu_vendor" || return 1
	set_state "GPU_LABEL" "$(gpu_vendor_label "$gpu_vendor")" || return 1
	set_state "CPU_VENDOR" "$cpu_vendor" || return 1
	case $boot_mode in
		uefi|bios)
			;;
		*)
			print_install_error "Unsupported boot mode: $boot_mode"
			return 1
			;;
	esac

	if [[ -z $disk ]]; then
		print_install_error "Select a target disk before starting the installation."
		return 1
	fi

	if [[ ! -b $disk ]]; then
		print_install_error "The saved disk does not exist anymore: $disk"
		return 1
	fi
	if type run_hooks >/dev/null 2>&1; then
		run_hooks pre_install "$disk" || true
	fi

	build_pacstrap_package_list "$boot_mode" "$filesystem" "$enable_zram" pacstrap_packages "$desktop_profile" "$display_manager" "$display_mode" "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" "$environment_vendor" "$gpu_vendor" "$secure_boot_mode" "$greeter_frontend"

	: > "$ARCHINSTALL_LOG" || {
		print_install_error "Could not write the install log: $ARCHINSTALL_LOG"
		return 1
	}

	if (
		ARCHINSTALL_INSTALL_SUCCESS=false
		ARCHINSTALL_CLEANUP_ACTIVE=true
		trap 'cleanup_install' EXIT
		trap 'on_install_sigint' INT

		log_line "Starting installation on $disk"
		log_line "Boot mode: $boot_mode"
		log_line "Secure Boot firmware state: $current_secure_boot_state"
		log_line "Secure Boot mode: $secure_boot_mode"
		log_line "Environment: $(environment_label "$environment_vendor")"
		log_line "GPU: $(gpu_vendor_label "$gpu_vendor")"
		log_line "Install scenario: $install_scenario"
		disk_type="$(detect_disk_type "$disk")"
		log_line "Disk type: $disk_type"
		set_state "DISK_TYPE" "$disk_type" || exit 1
		log_line "Filesystem: $filesystem"
		log_line "Zram: $enable_zram"
		log_line "Install profile: $install_profile"
		log_line "Desktop profile: $desktop_profile"
		log_line "Display mode: $display_mode"
		log_line "Display manager: $display_manager"
		log_line "Greeter frontend: $greeter_frontend"
		log_line "Encryption: $enable_luks"
		log_line "Snapshot provider: $snapshot_provider"
		log_line "Safe mode: $INSTALL_SAFE_MODE"

		resolve_display_mode() {
			local requested_mode=${1:-auto}
			local detected_virtualization="false"
			local has_drm_device="false"
			local has_gpu="false"

			case $requested_mode in
				wayland|x11)
					printf '%s\n' "$requested_mode"
					return 0
					;;
				auto)
					;;
				*)
					printf 'wayland\n'
					return 0
					;;
			esac

			if [[ $environment_vendor != "baremetal" ]]; then
				detected_virtualization="true"
			fi
			if compgen -G '/dev/dri/card*' >/dev/null 2>&1; then
				has_drm_device="true"
			fi
			if command -v lspci >/dev/null 2>&1 && lspci | grep -Eiq 'vga|3d|display'; then
				has_gpu="true"
			fi

			if [[ $detected_virtualization == "true" ]]; then
				printf 'x11\n'
				return 0
			fi
			if [[ $has_drm_device == "true" || $has_gpu == "true" ]]; then
				printf 'wayland\n'
				return 0
			fi

			printf 'x11\n'
		}

		resolved_display_mode="$(resolve_display_mode "$display_mode")"
		set_state "RESOLVED_DISPLAY_MODE" "$resolved_display_mode" || exit 1
		log_line "Resolved display mode: $resolved_display_mode"
		if flag_enabled "$DEV_MODE"; then
			log_line "DEV_MODE enabled: SKIP_PARTITION=$SKIP_PARTITION SKIP_PACSTRAP=$SKIP_PACSTRAP SKIP_CHROOT=$SKIP_CHROOT"
		fi

		run_step "Unmounting any previous install target" cleanup_mounts || exit 1
		log_stage 5 "Checking prerequisites"
		run_optional_step "Checking internet connectivity" ping -c 1 archlinux.org
		initialize_pacman_environment || exit 1

		if flag_enabled "$SKIP_PARTITION"; then
			log_line "Skipping partitioning and formatting because SKIP_PARTITION=$SKIP_PARTITION"
		elif [[ $install_scenario != "wipe" ]]; then
			log_line "Reusing prepared partition layout because INSTALL_SCENARIO=$install_scenario"
		else
			run_step "Wiping existing signatures on $disk" wipefs -a "$disk" || exit 1
			if [[ $boot_mode == "uefi" ]]; then
				run_step "Creating a GPT partition table" parted -s "$disk" mklabel gpt || exit 1
				run_step "Creating the EFI system partition" parted -s "$disk" mkpart ESP fat32 1MiB 1025MiB || exit 1
				run_step "Setting the EFI boot flag" parted -s "$disk" set 1 boot on || exit 1
				run_step "Setting the EFI ESP flag" parted -s "$disk" set 1 esp on || exit 1
				run_step "Creating the root partition" parted -s "$disk" mkpart ROOT ext4 1025MiB 100% || exit 1
			else
				run_step "Creating an MBR partition table" parted -s "$disk" mklabel msdos || exit 1
				run_step "Creating the root partition" parted -s "$disk" mkpart primary ext4 1MiB 100% || exit 1
				run_step "Marking the root partition bootable" parted -s "$disk" set 1 boot on || exit 1
			fi
			run_step "Refreshing the kernel partition table" partprobe "$disk" || exit 1

			if command -v udevadm >/dev/null 2>&1; then
				run_step "Waiting for partition device nodes" udevadm settle || exit 1
			fi
		fi

		mapfile -t resolved_partitions < <(resolve_target_partitions "$disk" "$boot_mode") || exit 1
		efi_partition=${resolved_partitions[0]:-}
		root_partition=${resolved_partitions[1]:-}
		[[ $efi_partition == "-" ]] && efi_partition=""

		if [[ -z $root_partition ]]; then
			print_install_error "Could not resolve the target partitions for: $disk"
			exit 1
		fi
		if [[ $boot_mode == "uefi" && -z $efi_partition ]]; then
			print_install_error "Could not resolve the EFI partition for: $disk"
			exit 1
		fi

		if [[ -n $efi_partition ]]; then
			set_state "EFI_PART" "$efi_partition" || exit 1
		else
			unset_state "EFI_PART" || exit 1
		fi
		set_state "BOOT_MODE" "$boot_mode" || exit 1
		set_state "ROOT_PART" "$root_partition" || exit 1
		set_state "ENABLE_LUKS" "$enable_luks" || exit 1
		set_state "LUKS_MAPPER_NAME" "$luks_mapper_name" || exit 1
		set_state "SNAPSHOT_PROVIDER" "$snapshot_provider" || exit 1

		log_stage 15 "Partitioning disk"
		if flag_enabled "$SKIP_PARTITION"; then
			log_line "Skipping filesystem creation because SKIP_PARTITION=$SKIP_PARTITION"
		else
			if [[ $boot_mode == "uefi" && $format_efi == "true" ]]; then
				run_step "Formatting the EFI partition as FAT32" mkfs.fat -F32 "$efi_partition" || exit 1
			fi
			if [[ $format_root == "true" ]]; then
				if flag_enabled "$enable_luks"; then
					root_mount_device="$(prepare_luks_root_device "$root_partition" "$luks_mapper_name" "${INSTALL_LUKS_PASSWORD:-}")" || exit 1
					set_state "ROOT_MAPPER" "$root_mount_device" || exit 1
					luks_partition_uuid="$(get_partition_uuid "$root_partition")" || exit 1
					set_state "LUKS_PART_UUID" "$luks_partition_uuid" || exit 1
					format_root_filesystem "$filesystem" "$root_mount_device" || exit 1
				else
					root_mount_device="$root_partition"
					format_root_filesystem "$filesystem" "$root_partition" || exit 1
				fi
			else
				log_line "Skipping root filesystem creation because FORMAT_ROOT=$format_root"
			fi
		fi

		if [[ -z $root_mount_device ]]; then
			if flag_enabled "$enable_luks"; then
				root_mount_device="$(open_luks_root_device "$root_partition" "$luks_mapper_name" "${INSTALL_LUKS_PASSWORD:-}")" || exit 1
				set_state "ROOT_MAPPER" "$root_mount_device" || exit 1
				if [[ -z ${luks_partition_uuid:-} ]]; then
					luks_partition_uuid="$(get_partition_uuid "$root_partition")" || exit 1
					set_state "LUKS_PART_UUID" "$luks_partition_uuid" || exit 1
				fi
			else
				root_mount_device="$root_partition"
			fi
		fi

		log_stage 25 "Mounting filesystems"
		mount_root_filesystem "$filesystem" "$disk_type" "$root_mount_device" || exit 1
		validate_target_mount "$root_mount_device" || exit 1
		expected_root_source="$(normalized_mount_source /mnt)"
		if [[ -z $expected_root_source ]]; then
			print_install_error "Could not determine the expected source for /mnt after mounting."
			exit 1
		fi
		log_line "[DEBUG] Locked /mnt to expected source: $expected_root_source"
		log_line "[DEBUG] Mount state after root mount"
		log_mount_state
		if [[ $boot_mode == "uefi" ]]; then
			validate_target_mount "$root_mount_device" "$expected_root_source" || exit 1
			run_step "Creating the EFI mount point" mkdir -p /mnt/boot || exit 1
			run_step "Mounting the EFI partition" mount "$efi_partition" /mnt/boot || exit 1
		fi
		validate_target_mount "$root_mount_device" "$expected_root_source" || exit 1
		log_partition_metadata "$root_partition" "$efi_partition"
		log_mounted_filesystems "$filesystem"
		required_space_mib="$(estimate_target_required_space_mib "$desktop_profile" "$filesystem")"
		validate_target_mount "$root_mount_device" "$expected_root_source" || exit 1
		run_step "Checking target free space" ensure_target_has_space /mnt "$required_space_mib" || exit 1

		if flag_enabled "$SKIP_PACSTRAP"; then
			log_line "Skipping pacstrap because SKIP_PACSTRAP=$SKIP_PACSTRAP"
			if ! verify_target_system_present "$root_mount_device" "$expected_root_source"; then
				print_install_error "SKIP_PACSTRAP=true requires an existing installed system mounted at /mnt."
				exit 1
			fi
			verify_base_system_files "$root_mount_device" "$expected_root_source" || exit 1
			log_installed_target_packages "$root_mount_device" "$expected_root_source" || exit 1
		else
			validate_target_mount "$root_mount_device" "$expected_root_source" || exit 1
			log_stage 35 "Downloading and installing packages (this may take several minutes)"
			# Remove legacy iptables if present to prevent pacman conflict with iptables-nft
			run_optional_step "Removing legacy iptables to prevent conflict" \
				pacman -Rdd iptables --noconfirm
			run_pacstrap_install "${pacstrap_packages[@]}" || exit 1
			log_line "[DEBUG] Mount state after pacstrap"
			log_mount_state
			validate_target_mount "$root_mount_device" "$expected_root_source" || exit 1
			verify_target_system_present "$root_mount_device" "$expected_root_source" || exit 1
			verify_base_system_files "$root_mount_device" "$expected_root_source" || exit 1
			log_line "[DEBUG] Verified required base system files after pacstrap"
			log_installed_target_packages "$root_mount_device" "$expected_root_source" || exit 1
		fi

		log_stage 75 "Configuring system"
		validate_target_mount "$root_mount_device" "$expected_root_source" || exit 1
		write_target_fstab "$filesystem" "$disk_type" "$root_mount_device" "$expected_root_source" "$efi_partition" || exit 1
		log_stage 82 "Generating fstab"

		if flag_enabled "$SKIP_CHROOT"; then
			log_line "Skipping chroot configuration because SKIP_CHROOT=$SKIP_CHROOT"
		else
			validate_target_mount "$root_mount_device" "$expected_root_source" || exit 1
			root_uuid="$(get_partition_uuid "$root_mount_device")" || exit 1
			if [[ $filesystem == "btrfs" ]]; then
				root_mount_options="$(btrfs_mount_options '@' "$disk_type")"
			else
				root_mount_options=""
			fi
			prepare_chroot_mounts "$root_mount_device" "$expected_root_source" || exit 1
			log_stage 88 "Running chroot configuration"
			run_chroot_configuration "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$root_mount_options" "$enable_zram" "$desktop_profile" "$display_manager" "$display_mode" "$resolved_display_mode" "$root_mount_device" "$expected_root_source" || exit 1
			log_stage 95 "Finalizing installation"
			if type run_hooks >/dev/null 2>&1; then
				run_hooks post_chroot "$disk" "$root_partition" || true
			fi
		fi

		# Copy install log to the new user's home directory for post-install reference
		local log_username
		log_username="$(get_state "USERNAME" 2>/dev/null || printf 'archuser')"
		if [[ -n $log_username && -d "/mnt/home/$log_username" ]]; then
			install -m 644 "$ARCHINSTALL_LOG" "/mnt/home/$log_username/archinstall.log" 2>>"$ARCHINSTALL_LOG" || true
			log_line "Install log saved to /mnt/home/$log_username/archinstall.log"
		fi

		# Generate install manifest for post-install reference
		local manifest_path="/mnt/home/$log_username/archinstall-manifest.txt"
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
				printf 'Filesystem  : %s\n' "$filesystem"
				printf 'Encryption  : %s\n' "$enable_luks"
				printf 'Snapshots   : %s\n' "$snapshot_provider"
				printf 'Zram        : %s\n' "$enable_zram"
				printf 'Boot Mode   : %s\n' "$boot_mode"
				printf 'Secure Boot : %s\n' "$secure_boot_mode"
				printf 'CPU Vendor  : %s\n' "$(get_state "CPU_VENDOR" 2>/dev/null || printf 'unknown')"
				printf 'GPU Vendor  : %s\n' "$(get_state "GPU_VENDOR" 2>/dev/null || printf 'unknown')"
				printf 'Environment : %s\n' "$(get_state "ENVIRONMENT_VENDOR" 2>/dev/null || printf 'unknown')"
				printf '\nDISK LAYOUT\n'
				printf '-----------\n'
				printf 'Device      : %s\n' "$disk"
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
				arch-chroot /mnt pacman -Q 2>/dev/null || printf '  (unavailable)\n'
			} > "$manifest_path" 2>/dev/null || true
			chmod 644 "$manifest_path" 2>/dev/null || true
			log_line "Install manifest saved to $manifest_path"
		fi

		ARCHINSTALL_INSTALL_SUCCESS=true
		ARCHINSTALL_CLEANUP_ACTIVE=false
		log_line "[ OK ] Installation completed successfully"
		log_line "Handing control back to the installer UI."
		if type run_hooks >/dev/null 2>&1; then
			run_hooks post_install "$disk" || true
		fi
		exit 0
	); then
		return 0
	else
		install_status=$?
	fi

	return "$install_status"
}
