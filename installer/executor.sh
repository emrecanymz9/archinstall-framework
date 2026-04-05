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

# shellcheck source=installer/ui/dialog.sh
source "$SCRIPT_DIR/ui/dialog.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh"
# shellcheck source=installer/core/hooks.sh
safe_source_module "$SCRIPT_DIR/core/hooks.sh" || true
# shellcheck source=installer/core/module-registry.sh
safe_source_module "$SCRIPT_DIR/core/module-registry.sh" || true
# shellcheck source=installer/core/plugin-loader.sh
safe_source_module "$SCRIPT_DIR/core/plugin-loader.sh" || true
# shellcheck source=installer/core/config.sh
safe_source_module "$SCRIPT_DIR/core/config.sh" || true
# shellcheck source=installer/core/system.sh
safe_source_module "$SCRIPT_DIR/core/system.sh" || true
# shellcheck source=installer/boot/loader.sh
safe_source_module "$SCRIPT_DIR/boot/loader.sh" || true
# shellcheck source=installer/core/hardware.sh
safe_source_module "$SCRIPT_DIR/core/hardware.sh" || true
# shellcheck source=installer/core/desktop.sh
safe_source_module "$SCRIPT_DIR/core/desktop.sh" || true
# shellcheck source=installer/postinstall/display-manager.sh
safe_source_module "$SCRIPT_DIR/postinstall/display-manager.sh" || true
# shellcheck source=installer/postinstall/packages.sh
safe_source_module "$SCRIPT_DIR/postinstall/packages.sh" || true
# shellcheck source=installer/features/secureboot.sh
safe_source_module "$SCRIPT_DIR/features/secureboot.sh" || true
# shellcheck source=installer/features/display.sh
safe_source_module "$SCRIPT_DIR/features/display.sh" || true
# shellcheck source=installer/features/gpu.sh
safe_source_module "$SCRIPT_DIR/features/gpu.sh" || true
# shellcheck source=installer/core/profiles.sh
safe_source_module "$SCRIPT_DIR/core/profiles.sh" || true
# shellcheck source=installer/core/network.sh
safe_source_module "$SCRIPT_DIR/core/network.sh" || true
# shellcheck source=installer/core/packages.sh
safe_source_module "$SCRIPT_DIR/core/packages.sh" || true
# shellcheck source=installer/core/luks.sh
safe_source_module "$SCRIPT_DIR/core/luks.sh" || true
# shellcheck source=installer/features/snapshots.sh
safe_source_module "$SCRIPT_DIR/features/snapshots.sh" || true
# shellcheck source=installer/features/steam.sh
safe_source_module "$SCRIPT_DIR/features/steam.sh" || true
# shellcheck source=installer/postinstall/finalize.sh
safe_source_module "$SCRIPT_DIR/postinstall/finalize.sh" || true
# shellcheck source=installer/postinstall/services.sh
safe_source_module "$SCRIPT_DIR/postinstall/services.sh" || true
# shellcheck source=installer/postinstall/logs.sh
safe_source_module "$SCRIPT_DIR/postinstall/logs.sh" || true
# shellcheck source=installer/postinstall/cleanup.sh
safe_source_module "$SCRIPT_DIR/postinstall/cleanup.sh" || true
# shellcheck source=installer/core/disk/layout.sh
safe_source_module "$SCRIPT_DIR/core/disk/layout.sh" || true
# shellcheck source=installer/core/disk/space.sh
safe_source_module "$SCRIPT_DIR/core/disk/space.sh" || true
# shellcheck source=installer/core/network.sh
safe_source_module "$SCRIPT_DIR/core/network.sh" || true
# shellcheck source=installer/core/gpu/driver.sh
safe_source_module "$SCRIPT_DIR/core/gpu/driver.sh" || true
# shellcheck source=installer/core/pipeline.sh
safe_source_module "$SCRIPT_DIR/core/pipeline.sh" || true

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

run_arch_chroot_with_timeout() {
	local chroot_timeout=${ARCHINSTALL_CHROOT_TIMEOUT:-0}

	if [[ $chroot_timeout =~ ^[0-9]+$ ]] && (( chroot_timeout > 0 )); then
		timeout "$chroot_timeout" arch-chroot "$@"
		return $?
	fi

	arch-chroot "$@"
}

log_arch_chroot_failure() {
	local status=${1:-1}
	local chroot_timeout=${ARCHINSTALL_CHROOT_TIMEOUT:-0}

	case $status in
		124)
			log_line "[FAIL] arch-chroot timed out after ${chroot_timeout:-0} seconds"
			print_install_error "arch-chroot timed out after ${chroot_timeout:-0} seconds. Cleanup will continue."
			;;
		*)
			log_line "[FAIL] arch-chroot exited with status $status"
			;;
	esac
}

lazy_unmount_path() {
	local target_path=${1:?target path is required}

	if mountpoint -q "$target_path" 2>> "$ARCHINSTALL_LOG"; then
		log_line "[DEBUG] Lazy unmounting $target_path"
		umount -l "$target_path" >> "$ARCHINSTALL_LOG" 2>&1 || true
	fi
}

cleanup_chroot_api_mounts() {
	lazy_unmount_path /mnt/sys
	lazy_unmount_path /mnt/proc
	lazy_unmount_path /mnt/dev
}

ext4_mount_options() {
	local disk_type
	local -a options=(defaults noatime)

	disk_type="$(normalize_disk_type "${1:-unknown}")"

	if [[ $disk_type == "ssd" || $disk_type == "nvme" ]]; then
		options+=(discard=async)
	fi

	join_by_comma "${options[@]}"
}

btrfs_mount_options() {
	local subvolume=${1:?subvolume is required}
	local disk_type
	local -a options=("subvol=$subvolume" compress=zstd noatime)

	disk_type="$(normalize_disk_type "${2:-unknown}")"

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
	local display_session=${7:-wayland}
	local install_profile=${8:-daily}
	local editor_choice=${9:-nano}
	local include_vscode=${10:-false}
	local custom_tools=${11:-}
	local environment_vendor=${12:-baremetal}
	local gpu_vendor=${13:-generic}
	local secure_boot_mode=${14:-disabled}
	local greeter=${15:-tuigreet}
	local install_steam=${16:-false}
	local snapshot_provider=${17:-none}
	local enable_luks=${18:-false}
	local bootloader=${19:-$(default_bootloader_for_mode "$boot_mode")}
	local cpu_vendor=${20:-unknown}
	local environment_type=${21:-unknown}

	package_ref=()
	if declare -F resolve_package_strategy >/dev/null 2>&1; then
		resolve_package_strategy "$boot_mode" "$filesystem" "$enable_zram" "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" "$desktop_profile" "$display_manager" "$display_session" "$environment_vendor" "$gpu_vendor" "$secure_boot_mode" "$greeter" "$snapshot_provider" "$enable_luks" "$install_steam" "$bootloader" "$cpu_vendor" "$environment_type" package_ref || return 1
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

preflight_checks() {
	log_line "[PREFLIGHT] Running pre-install checks"
	local missing_critical=()
	local cmd
	local mnt_contents=""

	for cmd in pacstrap arch-chroot lsblk parted genfstab; do
		command -v "$cmd" >/dev/null 2>&1 || missing_critical+=("$cmd")
	done

	if [[ ${#missing_critical[@]} -gt 0 ]]; then
		print_install_error "Preflight check failed: required commands not found: ${missing_critical[*]}"
		log_line "[PREFLIGHT] FAIL — missing: ${missing_critical[*]}"
		return 1
	fi

	if ! ping -c 1 -W 3 archlinux.org >/dev/null 2>&1; then
		log_line "[PREFLIGHT] WARNING: no internet connectivity detected"
		print_install_error "Preflight warning: no internet connectivity. Package installation may fail."
	fi

	if mountpoint -q /mnt 2>/dev/null; then
		log_line "[PREFLIGHT] FAIL — /mnt is already mounted"
		error_exit "Preflight check failed: /mnt is already mounted. Unmount it before starting the installation."
	fi

	if [[ -d /mnt ]] && [[ -n "$(ls -A /mnt 2>/dev/null)" ]]; then
		log_line "[PREFLIGHT] FAIL — /mnt is not empty before install"
		error_exit "/mnt is not empty. Previous installation residue detected. Clean /mnt before continuing."
	fi

	log_line "[PREFLIGHT] All checks passed"
	return 0
}

require_commands() {
	local cmd
	local missing=()
	local boot_mode=""
	local filesystem=""
	local enable_luks=""
	local selected_bootloader=""
	local -a boot_commands=()

	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || printf 'bios')"
	filesystem="$(normalize_filesystem "$(get_state "FILESYSTEM" 2>/dev/null || printf 'ext4')")"
	enable_luks="$(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false')"
	selected_bootloader="$(normalize_bootloader "$(get_state "BOOTLOADER" 2>/dev/null || printf '')" "$boot_mode")"

	for cmd in lsblk wipefs parted partprobe mkfs.ext4 mount umount pacman pacstrap ping blkid arch-chroot tee tail findmnt genfstab mountpoint; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done
	if [[ ${UI_MODE:-dialog} == "dialog" ]]; then
		command -v dialog >/dev/null 2>&1 || missing+=("dialog")
	fi

	if [[ $boot_mode == "uefi" ]]; then
		command -v mkfs.fat >/dev/null 2>&1 || missing+=("mkfs.fat")
	fi
	if declare -F bootloader_required_commands >/dev/null 2>&1; then
		bootloader_required_commands "$selected_bootloader" "$boot_mode" boot_commands || return 1
		for cmd in "${boot_commands[@]}"; do
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

enable_multilib_repo() {
	local pacman_conf=${1:?pacman configuration path is required}

	if [[ ! -f $pacman_conf ]]; then
		return 1
	fi

	if grep -q '^#\[multilib\]' "$pacman_conf"; then
		sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' "$pacman_conf"
	fi
	if ! grep -q '^\[multilib\]' "$pacman_conf"; then
		cat >> "$pacman_conf" <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
	fi
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

error_exit() {
	local message=${1:-"Fatal error"}

	print_install_error "$message"
	log_line "[FATAL] $message"
	exit 1
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
		log_line "[DEBUG] Killing processes using /mnt before unmount"
		fuser -km /mnt >> "$ARCHINSTALL_LOG" 2>&1 || true
		cleanup_chroot_api_mounts
		if ! umount -R /mnt >> "$ARCHINSTALL_LOG" 2>&1; then
			log_line "[WARN] umount -R /mnt failed; attempting lazy unmount"
			if ! umount -l -R /mnt >> "$ARCHINSTALL_LOG" 2>&1; then
				log_line "[FAIL] Could not unmount /mnt after fuser kill and lazy fallback"
				print_install_error "Failed to unmount /mnt. Resolve manually before retrying the installation."
				return 1
			fi
		fi
	fi
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

is_core_pacstrap_package() {
	case ${1:-} in
		base|linux|linux-firmware|mkinitcpio|sudo|networkmanager|shadow|pambase)
			return 0
			;;
		*)
			return 1
			;;
	esac
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
	local -a core_packages=(base linux linux-firmware mkinitcpio sudo networkmanager shadow pambase)
	local -a requested_packages=("$@")
	local -a optional_packages=()
	local -a validated_optional_packages=()
	local package_name=""

	for package_name in "${requested_packages[@]}"; do
		[[ -n $package_name ]] || continue
		if is_core_pacstrap_package "$package_name"; then
			continue
		fi
		append_unique_items optional_packages "$package_name"
	done

	log_line "[DEBUG] Core pacstrap packages: ${core_packages[*]}"
	run_step_with_retry "Installing core Arch Linux packages" 3 \
		pacstrap -K /mnt "${core_packages[@]}" --noconfirm || return 1

	if [[ ${#optional_packages[@]} -eq 0 ]]; then
		log_line "[DEBUG] No optional packages were requested"
		return 0
	fi

	log_line "[DEBUG] Optional pacstrap package candidates: ${optional_packages[*]}"
	filter_valid_packages optional_packages validated_optional_packages
	if [[ ${#validated_optional_packages[@]} -eq 0 ]]; then
		log_line "[DEBUG] No optional packages remained after validation"
		return 0
	fi

	log_line "[DEBUG] Optional pacstrap package list: ${validated_optional_packages[*]}"
	run_step_with_retry "Installing optional Arch Linux packages" 3 \
		pacstrap /mnt "${validated_optional_packages[@]}" --noconfirm
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
	run_optional_step "Recording installed target packages" timeout 300 arch-chroot /mnt pacman -Q
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
	local display_session=${9:-wayland}
	local resolved_display_session=${10:-wayland}
	local greeter=""
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
	local quoted_greeter=""
	local quoted_display_session=""
	local quoted_resolved_display_session=""
	local bootloader=""
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
	local install_steam=""
	local enable_luks=""
	local luks_mapper_name=""
	local luks_partition_uuid=""
	local mkinitcpio_hooks=""
	local quoted_install_profile=""
	local quoted_bootloader=""
	local quoted_editor_choice=""
	local quoted_include_vscode=""
	local quoted_custom_tools=""
	local quoted_secure_boot_mode=""
	local quoted_current_secure_boot_state=""
	local quoted_current_secure_boot_setup_mode=""
	local quoted_environment_vendor=""
	local quoted_gpu_vendor=""
	local quoted_snapshot_provider=""
	local quoted_install_steam=""
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
	bootloader="$(normalize_bootloader "$(get_state "BOOTLOADER" 2>/dev/null || printf '')" "$boot_mode")"
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
	install_steam="$(get_state "INSTALL_STEAM" 2>/dev/null || printf 'false')"
	enable_luks="$(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false')"
	luks_mapper_name="$(get_state "LUKS_MAPPER_NAME" 2>/dev/null || printf 'cryptroot')"
	luks_partition_uuid="$(get_state "LUKS_PART_UUID" 2>/dev/null || printf '')"
	mkinitcpio_hooks="$(luks_mkinitcpio_hooks 2>/dev/null || printf 'base udev autodetect modconf block filesystems keyboard fsck')"
	greeter="$(get_state "GREETER" 2>/dev/null || printf 'none')"

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
	printf -v quoted_greeter '%q' "$greeter"
	printf -v quoted_display_session '%q' "$display_session"
	printf -v quoted_resolved_display_session '%q' "$resolved_display_session"
	printf -v quoted_install_profile '%q' "$install_profile"
	printf -v quoted_bootloader '%q' "$bootloader"
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
	printf -v quoted_install_steam '%q' "$install_steam"
	printf -v quoted_enable_luks '%q' "$enable_luks"
	printf -v quoted_luks_mapper_name '%q' "$luks_mapper_name"
	printf -v quoted_luks_partition_uuid '%q' "$luks_partition_uuid"
	printf -v quoted_mkinitcpio_hooks '%q' "$mkinitcpio_hooks"

	# Fail fast: locale and username must be set before entering chroot
	if [[ -z $locale ]]; then
		print_install_error "Locale is not set. Configure the install profile before starting."
		return 1
	fi
	if [[ -z $username ]]; then
		print_install_error "Username is not set. Configure the install profile before starting."
		return 1
	fi
	if [[ ! $username =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
		print_install_error "Username '${username}' is not valid. Use only lowercase letters, digits, underscores, and hyphens."
		return 1
	fi

	# Write all install variables to a file the chroot scripts source
	local env_file=/mnt/root/.install_env
	install -m 600 /dev/null "$env_file" || {
		print_install_error "Could not create chroot environment file: $env_file"
		return 1
	}
	{
		printf 'BOOT_MODE=%s\n' "$quoted_boot_mode"
		printf 'TARGET_DISK=%s\n' "$quoted_disk"
		printf 'ROOT_UUID=%s\n' "$quoted_root_uuid"
		printf 'TARGET_HOSTNAME=%s\n' "$quoted_hostname"
		printf 'TARGET_TIMEZONE=%s\n' "$quoted_timezone"
		printf 'TARGET_LOCALE=%s\n' "$quoted_locale"
		printf 'TARGET_KEYMAP=%s\n' "$quoted_keymap"
		printf 'TARGET_USERNAME=%s\n' "$quoted_username"
		printf 'TARGET_USER_PASSWORD=%s\n' "$quoted_user_password"
		printf 'TARGET_ROOT_PASSWORD=%s\n' "$quoted_root_password"
		printf 'TARGET_FILESYSTEM=%s\n' "$quoted_filesystem"
		printf 'TARGET_ROOT_MOUNT_OPTIONS=%s\n' "$quoted_root_mount_options"
		printf 'TARGET_ENABLE_ZRAM=%s\n' "$quoted_enable_zram"
		printf 'TARGET_DESKTOP_PROFILE=%s\n' "$quoted_desktop_profile"
		printf 'TARGET_DISPLAY_MANAGER=%s\n' "$quoted_display_manager"
		printf 'TARGET_GREETER=%s\n' "$quoted_greeter"
		printf 'TARGET_DISPLAY_SESSION=%s\n' "$quoted_display_session"
		printf 'TARGET_RESOLVED_DISPLAY_SESSION=%s\n' "$quoted_resolved_display_session"
		printf 'TARGET_INSTALL_PROFILE=%s\n' "$quoted_install_profile"
		printf 'TARGET_BOOTLOADER=%s\n' "$quoted_bootloader"
		printf 'TARGET_EDITOR_CHOICE=%s\n' "$quoted_editor_choice"
		printf 'TARGET_INCLUDE_VSCODE=%s\n' "$quoted_include_vscode"
		printf 'TARGET_CUSTOM_TOOLS=%s\n' "$quoted_custom_tools"
		printf 'TARGET_SECURE_BOOT_MODE=%s\n' "$quoted_secure_boot_mode"
		printf 'TARGET_CURRENT_SECURE_BOOT_STATE=%s\n' "$quoted_current_secure_boot_state"
		printf 'TARGET_SECURE_BOOT_SETUP_MODE=%s\n' "$quoted_current_secure_boot_setup_mode"
		printf 'TARGET_ENVIRONMENT_VENDOR=%s\n' "$quoted_environment_vendor"
		printf 'TARGET_ENVIRONMENT_TYPE=%s\n' "$quoted_environment_type"
		printf 'TARGET_GPU_VENDOR=%s\n' "$quoted_gpu_vendor"
		printf 'TARGET_SNAPSHOT_PROVIDER=%s\n' "$quoted_snapshot_provider"
		printf 'TARGET_INSTALL_STEAM=%s\n' "$quoted_install_steam"
		printf 'TARGET_LUKS_ENABLED=%s\n' "$quoted_enable_luks"
		printf 'TARGET_LUKS_MAPPER_NAME=%s\n' "$quoted_luks_mapper_name"
		printf 'LUKS_UUID=%s\n' "$quoted_luks_partition_uuid"
		printf 'TARGET_MKINITCPIO_HOOKS=%s\n' "$quoted_mkinitcpio_hooks"
		printf "PACMAN_OPTS='%s'\n" "${PACMAN_OPTS:---noconfirm --needed}"
		printf 'export BOOT_MODE TARGET_DISK ROOT_UUID TARGET_HOSTNAME TARGET_TIMEZONE TARGET_LOCALE TARGET_KEYMAP\n'
		printf 'export TARGET_USERNAME TARGET_USER_PASSWORD TARGET_ROOT_PASSWORD\n'
		printf 'export TARGET_FILESYSTEM TARGET_ROOT_MOUNT_OPTIONS TARGET_ENABLE_ZRAM\n'
		printf 'export TARGET_DESKTOP_PROFILE TARGET_DISPLAY_MANAGER TARGET_GREETER TARGET_DISPLAY_SESSION TARGET_RESOLVED_DISPLAY_SESSION\n'
		printf 'export TARGET_INSTALL_PROFILE TARGET_BOOTLOADER TARGET_EDITOR_CHOICE TARGET_INCLUDE_VSCODE TARGET_CUSTOM_TOOLS\n'
		printf 'export TARGET_SECURE_BOOT_MODE TARGET_CURRENT_SECURE_BOOT_STATE TARGET_SECURE_BOOT_SETUP_MODE\n'
		printf 'export TARGET_ENVIRONMENT_VENDOR TARGET_ENVIRONMENT_TYPE TARGET_GPU_VENDOR\n'
		printf 'export TARGET_SNAPSHOT_PROVIDER TARGET_INSTALL_STEAM\n'
		printf 'export TARGET_LUKS_ENABLED TARGET_LUKS_MAPPER_NAME LUKS_UUID TARGET_MKINITCPIO_HOOKS PACMAN_OPTS\n'
	} >> "$env_file"
	log_line "[DEBUG] Chroot environment file written to $env_file"

	cat <<EOF
set -euo pipefail

	cleanup_chroot_jobs() {
		local job_pid=""

		for job_pid in 4(jobs -pr 2>/dev/null || true); do
			kill "4job_pid" >/dev/null 2>&1 || true
		done
		wait >/dev/null 2>&1 || true
	}

	trap cleanup_chroot_jobs EXIT

# shellcheck source=/dev/null
source /root/.install_env

log_chroot_step() {
	echo "[STEP] \$1"
}

build_pacman_opts_array() {
	local -a opts=()
	read -r -a opts <<< "\${PACMAN_OPTS:---noconfirm --needed}"
	printf '%s\0' "\${opts[@]}"
}

install_packages_if_missing() {
	local package_name=""
	local missing=()
	local -a pacman_opts=()

	while IFS= read -r -d '' package_name; do
		[[ -n \$package_name ]] || continue
		if ! pacman -Q "\$package_name" >/dev/null 2>&1; then
			missing+=("\$package_name")
		fi
	done < <(printf '%s\0' "\$@")

	if (( \${#missing[@]} == 0 )); then
		return 0
	fi

	while IFS= read -r -d '' package_name; do
		pacman_opts+=("\$package_name")
	done < <(build_pacman_opts_array)

	pacman -S "\${pacman_opts[@]}" "\${missing[@]}"
}

$(postinstall_finalize_chroot_snippet)

$(postinstall_services_chroot_snippet)

$(bootloader_common_chroot_snippet)

$(steam_chroot_setup_snippet "$(get_state "INSTALL_STEAM" 2>/dev/null || printf 'false')")

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

if [[ \$TARGET_SECURE_BOOT_MODE == "disabled" || \$BOOT_MODE != "uefi" ]]; then
	log_chroot_step "Rebuilding initramfs"
	mkinitcpio -P || true
fi

$(postinstall_packages_chroot_snippet)

$(display_manager_chroot_snippet "$(get_state "DESKTOP_PROFILE" 2>/dev/null || printf 'none')")

if type emit_chroot_snippets >/dev/null 2>&1; then
	emit_chroot_snippets
fi

$(emit_bootloader_chroot_snippet "$(normalize_bootloader "$(get_state "BOOTLOADER" 2>/dev/null || printf '')" "$boot_mode")" "$boot_mode")

run_postinstall_service_enablement

$(secure_boot_chroot_snippet)
$(postinstall_cleanup_chroot_snippet)
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
	local display_session=${9:-wayland}
	local resolved_display_session=${10:-wayland}
	local root_partition=${11:-}
	local expected_root_source=${12:-}
	local chroot_status=1

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
		build_chroot_script "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$root_mount_options" "$enable_zram" "$desktop_profile" "$display_manager" "$display_session" "$resolved_display_session" | run_arch_chroot_with_timeout /mnt /bin/bash -s 2>&1 | sanitize_stream | tee_install_logs >/dev/null
		chroot_status=${PIPESTATUS[1]:-1}
	else
		build_chroot_script "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$root_mount_options" "$enable_zram" "$desktop_profile" "$display_manager" "$display_session" "$resolved_display_session" | run_arch_chroot_with_timeout /mnt /bin/bash -s 2>&1 | sanitize_stream | tee_install_logs
		chroot_status=${PIPESTATUS[1]:-1}
	fi

	if [[ $chroot_status -eq 0 ]]; then
		log_line "[ OK ] Configuring the target system inside chroot"
		return 0
	fi

	log_arch_chroot_failure "$chroot_status"
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
	local bootloader=""
	local environment_vendor="baremetal"
	local gpu_vendor="generic"
	local install_scenario=""
	local format_root="true"
	local format_efi="true"
	local desktop_profile=""
	local display_manager=""
	local greeter="tuigreet"
	local display_session="wayland"
	local resolved_display_session="wayland"
	local enable_luks="false"
	local luks_mapper_name="cryptroot"
	local snapshot_provider="none"
	local install_steam="false"
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
	preflight_checks || return 1

	disk="$(get_state "DISK" 2>/dev/null || true)"
	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || true)"
	filesystem="$(normalize_filesystem "$(get_state "FILESYSTEM" 2>/dev/null || printf 'ext4')")"
	enable_zram="$(get_state "ENABLE_ZRAM" 2>/dev/null || printf 'false')"
	install_profile="$(get_state "INSTALL_PROFILE" 2>/dev/null || printf 'daily')"
	editor_choice="$(get_state "EDITOR_CHOICE" 2>/dev/null || printf 'nano')"
	include_vscode="$(get_state "INCLUDE_VSCODE" 2>/dev/null || printf 'false')"
	custom_tools="$(get_state "CUSTOM_TOOLS" 2>/dev/null || printf '')"
	secure_boot_mode="$(get_state "SECURE_BOOT_MODE" 2>/dev/null || printf 'disabled')"
	install_scenario="$(get_state "INSTALL_SCENARIO" 2>/dev/null || true)"
	if [[ -z $install_scenario ]]; then
		print_install_error "INSTALL_SCENARIO is not set. Complete the Partition step before starting the installation."
		return 1
	fi
	case $install_scenario in
		wipe|dual-boot|free-space|manual) ;;
		*)
			print_install_error "Invalid INSTALL_SCENARIO: '$install_scenario'. Expected: wipe, dual-boot, free-space, or manual."
			return 1
			;;
	esac
	bootloader="$(normalize_bootloader "$(get_state "BOOTLOADER" 2>/dev/null || printf '')" "$(get_state "BOOT_MODE" 2>/dev/null || printf 'bios')")"
	format_root="$(get_state "FORMAT_ROOT" 2>/dev/null || printf 'true')"
	format_efi="$(get_state "FORMAT_EFI" 2>/dev/null || printf 'true')"
	desktop_profile="$(get_state "DESKTOP_PROFILE" 2>/dev/null || printf 'none')"
	display_manager="$(get_state "DISPLAY_MANAGER" 2>/dev/null || printf 'none')"
	greeter="$(get_state "GREETER" 2>/dev/null || printf 'none')"
	display_session="$(get_state "DISPLAY_SESSION" 2>/dev/null || printf 'wayland')"
	enable_luks="$(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false')"
	luks_mapper_name="$(get_state "LUKS_MAPPER_NAME" 2>/dev/null || printf 'cryptroot')"
	snapshot_provider="$(get_state "SNAPSHOT_PROVIDER" 2>/dev/null || printf 'none')"
	install_steam="$(get_state "INSTALL_STEAM" 2>/dev/null || printf 'false')"
	if type refresh_runtime_system_state >/dev/null 2>&1; then
		refresh_runtime_system_state >/dev/null 2>&1 || return 1
	fi
	if type refresh_hardware_state >/dev/null 2>&1; then
		refresh_hardware_state >/dev/null 2>&1 || return 1
	fi
	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || printf 'bios')"
	current_secure_boot_state="$(get_state "CURRENT_SECURE_BOOT_STATE" 2>/dev/null || printf 'unsupported')"
	environment_vendor="$(get_state "ENVIRONMENT_VENDOR" 2>/dev/null || printf 'unknown')"
	gpu_vendor="$(get_state "GPU_VENDOR" 2>/dev/null || printf 'generic')"
	local cpu_vendor
	local environment_type
	cpu_vendor="$(get_state "CPU_VENDOR" 2>/dev/null || printf 'unknown')"
	environment_type="$(get_state "ENVIRONMENT_TYPE" 2>/dev/null || printf 'unknown')"
	apply_display_state "$desktop_profile" display_session display_manager greeter || return 1
	resolved_display_session="$(state_or_default "DISPLAY_SESSION" "$(normalize_display_session "$display_session")")"
	set_state "BOOTLOADER" "$(normalize_bootloader "$bootloader" "$boot_mode")" || return 1
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

	build_pacstrap_package_list "$boot_mode" "$filesystem" "$enable_zram" pacstrap_packages "$desktop_profile" "$display_manager" "$resolved_display_session" "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" "$environment_vendor" "$gpu_vendor" "$secure_boot_mode" "$greeter" "$install_steam" "$snapshot_provider" "$enable_luks" "$bootloader" "$cpu_vendor" "$environment_type"

	: > "$ARCHINSTALL_LOG" || {
		print_install_error "Could not write the install log: $ARCHINSTALL_LOG"
		return 1
	}

	if (
		ARCHINSTALL_INSTALL_SUCCESS=false
		ARCHINSTALL_CLEANUP_ACTIVE=true
		trap 'cleanup_install' EXIT
		trap 'on_install_sigint' INT

		run_install_pipeline || exit 1

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
