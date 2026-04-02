#!/usr/bin/env bash

resolve_package_strategy() {
	local boot_mode=${1:?boot mode is required}
	local filesystem=${2:?filesystem is required}
	local enable_zram=${3:?zram flag is required}
	local install_profile=${4:-daily}
	local editor_choice=${5:-nano}
	local include_vscode=${6:-false}
	local custom_tools=${7:-}
	local desktop_profile=${8:-none}
	local display_manager=${9:-none}
	local display_mode=${10:-auto}
	local environment_vendor=${11:-baremetal}
	local gpu_vendor=${12:-generic}
	local secure_boot_mode=${13:-disabled}
	local greeter_frontend=${14:-tuigreet}
	local snapshot_provider=${15:-none}
	local enable_luks=${16:-false}
	local -n package_ref=${17:?package reference is required}
	local -a base_packages=()
	local -a profile_packages=()
	local -a hardware_packages=()
	local -a desktop_packages=()
	local -a secure_boot_packages_ref=()
	local -a snapshot_packages=()
	local -a encryption_packages=()

	package_ref=()
	get_final_packages "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" base_packages || return 1
	append_unique_packages package_ref "${base_packages[@]}"

	install_profile_packages "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" profile_packages || return 1
	hardware_profile_packages "$environment_vendor" "$gpu_vendor" "$desktop_profile" hardware_packages || return 1
	secure_boot_packages "$secure_boot_mode" "$boot_mode" secure_boot_packages_ref || return 1
	append_unique_packages package_ref "${profile_packages[@]}"
	append_unique_packages package_ref "${hardware_packages[@]}"
	append_unique_packages package_ref "${secure_boot_packages_ref[@]}"

	if desktop_profile_packages "$desktop_profile" "$display_manager" "$display_mode" desktop_packages "$greeter_frontend"; then
		append_unique_packages package_ref "${desktop_packages[@]}"
	fi

	if [[ $filesystem == "btrfs" ]]; then
		append_unique_packages package_ref btrfs-progs
	fi
	if [[ $boot_mode == "bios" ]]; then
		append_unique_packages package_ref grub
	fi
	if declare -F flag_enabled >/dev/null 2>&1 && flag_enabled "$enable_zram"; then
		append_unique_packages package_ref zram-generator
	fi
	if declare -F luks_required_packages >/dev/null 2>&1; then
		luks_required_packages "$enable_luks" encryption_packages || return 1
		append_unique_packages package_ref "${encryption_packages[@]}"
	fi
	if declare -F snapshot_required_packages >/dev/null 2>&1; then
		snapshot_required_packages "$snapshot_provider" "$filesystem" snapshot_packages || return 1
		append_unique_packages package_ref "${snapshot_packages[@]}"
	fi
	if type list_plugin_packages >/dev/null 2>&1; then
		mapfile -t profile_packages < <(list_plugin_packages)
		append_unique_packages package_ref "${profile_packages[@]}"
	fi
	if type expand_package_dependencies >/dev/null 2>&1; then
		expand_package_dependencies package_ref || true
	fi
}

register_packages_module() {
	archinstall_register_module "packages" "Package strategy engine" "resolve_package_strategy"
}