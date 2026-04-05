#!/usr/bin/env bash

PROFILES_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCHINSTALL_PACKAGES_CONFIG_PATH="$(cd -- "$PROFILES_MODULE_DIR/../.." && pwd)/config/packages.conf"
ARCHINSTALL_SYSTEM_CONFIG_PATH="$(cd -- "$PROFILES_MODULE_DIR/../.." && pwd)/config/system.conf"
ARCHINSTALL_SYSTEM_CONFIG_LOADED=${ARCHINSTALL_SYSTEM_CONFIG_LOADED:-false}

load_system_package_config() {
	ARCHINSTALL_SYSTEM_CONFIG_STATUS=${ARCHINSTALL_SYSTEM_CONFIG_STATUS:-missing}

	if [[ ${ARCHINSTALL_SYSTEM_CONFIG_LOADED:-false} == "true" ]]; then
		return 0
	fi

	if [[ -r $ARCHINSTALL_PACKAGES_CONFIG_PATH ]] && bash -n "$ARCHINSTALL_PACKAGES_CONFIG_PATH" >/dev/null 2>&1; then
		# shellcheck disable=SC1090
		source "$ARCHINSTALL_PACKAGES_CONFIG_PATH" || true
		ARCHINSTALL_SYSTEM_CONFIG_STATUS=loaded
	elif [[ -r $ARCHINSTALL_SYSTEM_CONFIG_PATH ]] && bash -n "$ARCHINSTALL_SYSTEM_CONFIG_PATH" >/dev/null 2>&1; then
		# shellcheck disable=SC1090
		source "$ARCHINSTALL_SYSTEM_CONFIG_PATH" || true
		ARCHINSTALL_SYSTEM_CONFIG_STATUS=loaded
	else
		if [[ -r $ARCHINSTALL_SYSTEM_CONFIG_PATH ]]; then
			ARCHINSTALL_SYSTEM_CONFIG_STATUS=invalid
		else
			ARCHINSTALL_SYSTEM_CONFIG_STATUS=missing
		fi
	fi

	ARCHINSTALL_SYSTEM_CONFIG_LOADED=true
}

package_config_status() {
	load_system_package_config
	printf '%s\n' "${ARCHINSTALL_SYSTEM_CONFIG_STATUS:-missing}"
}

package_config_warning_text() {
	case $(package_config_status) in
		loaded)
			return 1
			;;
		invalid)
			printf 'Package config exists but has invalid syntax. Safe defaults will be used.\n'
			;;
		*)
			printf 'Package config is missing. Safe defaults will be used.\n'
			;;
	esac
}

config_csv_or_default() {
	local variable_name=${1:?variable name is required}
	local default_value=${2-}

	load_system_package_config
	printf '%s\n' "${!variable_name:-$default_value}"
}

append_unique_packages() {
	local -n target_ref=${1:?target reference is required}
	local package_name=""
	local existing=""
	local duplicate="false"

	shift
	for package_name in "$@"; do
		[[ -n $package_name ]] || continue
		duplicate="false"
		for existing in "${target_ref[@]}"; do
			if [[ $existing == "$package_name" ]]; then
				duplicate="true"
				break
			fi
		done
		if [[ $duplicate != "true" ]]; then
			target_ref+=("$package_name")
		fi
	done
}

append_csv_packages() {
	local csv_value=${1:-}
	local -n package_ref=${2:?package reference is required}
	local -a parsed_packages=()
	local package_name=""

	[[ -n $csv_value ]] || return 0
	IFS=',' read -r -a parsed_packages <<< "$csv_value"
	for package_name in "${parsed_packages[@]}"; do
		[[ -n $package_name ]] || continue
		append_unique_packages package_ref "$package_name"
	done
}

profile_config_csv() {
	local prefix=${1:?prefix is required}
	local profile=${2:?profile is required}
	local default_value=${3-}

	config_csv_or_default "${prefix}_${profile}" "$default_value"
}

editor_packages_csv() {
	local editor_choice=${1:-nano}
	local default_value=""

	case $editor_choice in
		nano|micro|vim|kate)
			default_value=$editor_choice
			;;
		*)
			default_value="nano"
			;;
	esac

	config_csv_or_default "ARCHINSTALL_EDITOR_PACKAGES_${editor_choice}" "$default_value"
}

visible_tool_label() {
	local tool_id=${1:?tool id is required}
	config_csv_or_default "ARCHINSTALL_TOOL_LABEL_${tool_id}" "$tool_id"
}

package_dependency_config_key() {
	local package_name=${1:?package name is required}
	local normalized_name=""

	normalized_name="${package_name//-/_}"
	normalized_name="${normalized_name//./_}"
	printf 'ARCHINSTALL_PACKAGE_DEPENDS_%s\n' "$normalized_name"
}

package_dependencies_csv() {
	local package_name=${1:?package name is required}
	local config_key=""

	config_key="$(package_dependency_config_key "$package_name")"
	config_csv_or_default "$config_key" ""
}

expand_package_dependencies() {
	local -n package_ref=${1:?package reference is required}
	local changed="true"
	local package_name=""
	local dependency_csv=""
	local -a snapshot=()

	while [[ $changed == "true" ]]; do
		changed="false"
		snapshot=("${package_ref[@]}")
		for package_name in "${snapshot[@]}"; do
			local before_count=${#package_ref[@]}
			dependency_csv="$(package_dependencies_csv "$package_name")"
			if [[ -z $dependency_csv ]]; then
				continue
			fi
			append_csv_packages "$dependency_csv" package_ref
			if [[ ${#package_ref[@]} -ne $before_count ]]; then
				changed="true"
			fi
		done
	done
}

profile_default_visible_tools() {
	local install_profile=${1:-custom}

	case $install_profile in
		daily)
			profile_config_csv "ARCHINSTALL_DEFAULT_VISIBLE_TOOLS" "daily" "git,curl,fastfetch"
			;;
		dev)
			profile_config_csv "ARCHINSTALL_DEFAULT_VISIBLE_TOOLS" "dev" "git,curl,fastfetch,ripgrep,fd,manuals"
			;;
		custom)
			profile_config_csv "ARCHINSTALL_DEFAULT_VISIBLE_TOOLS" "custom" ""
			;;
		*)
			printf '\n'
			;;
	esac
}

install_profile_label() {
	case ${1:-daily} in
		daily)
			printf 'DAILY\n'
			;;
		dev)
			printf 'DEV\n'
			;;
		custom)
			printf 'CUSTOM\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

editor_choice_label() {
	case ${1:-nano} in
		nano)
			printf 'nano\n'
			;;
		micro)
			printf 'micro\n'
			;;
		vim)
			printf 'vim\n'
			;;
		kate)
			printf 'kate\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

select_install_profile() {
	local current_profile=${1:-daily}

	menu "Install Profile" "Choose the installer profile.\n\nCurrent: $(install_profile_label "$current_profile")" 16 76 4 \
		"daily" "Full KDE workstation with tools and minimal questions" \
		"dev" "Developer-oriented package set" \
		"custom" "Choose editors, tools, and optional components"

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

select_editor_choice() {
	local current_editor=${1:-nano}

	menu "Editors" "Choose the preferred editor package.\n\nCurrent: $(editor_choice_label "$current_editor")" 16 70 5 \
		"nano" "Small and familiar terminal editor" \
		"micro" "Friendly terminal editor with modern defaults" \
		"vim" "Modal editor for keyboard-driven workflows" \
		"kate" "KDE graphical editor"

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

profile_default_desktop_profile() {
	case ${1:-daily} in
		daily)
			printf 'kde\n'
			;;
		*)
			printf 'none\n'
			;;
	esac
}

profile_default_display_manager() {
	local install_profile=${1:-daily}
	local desktop_profile=${2:-$(profile_default_desktop_profile "$install_profile")}

	case "$install_profile:$desktop_profile" in
		daily:kde)
			printf 'sddm\n'
			;;
		*:kde)
			printf 'sddm\n'
			;;
		*)
			printf 'none\n'
			;;
	esac
}

profile_default_display_session() {
	case ${1:-daily} in
		daily|dev|custom)
			printf 'wayland\n'
			;;
		*)
			printf 'wayland\n'
			;;
	esac
}

csv_has_value() {
	local csv=${1:-}
	local needle=${2:-}
	local item=""

	IFS=',' read -r -a _csv_items <<< "$csv"
	for item in "${_csv_items[@]}"; do
		if [[ $item == "$needle" ]]; then
			return 0
		fi
	done

	return 1
}

install_profile_packages() {
	local install_profile=${1:-daily}
	local editor_choice=${2:-nano}
	local include_vscode=${3:-false}
	local custom_tools=${4:-}
	local -n package_ref=${5:?package reference is required}

	get_user_packages "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" package_ref
}

get_base_packages() {
	local -n package_ref=${1:?package reference is required}

	package_ref=()
	append_csv_packages "$(config_csv_or_default "ARCHINSTALL_BASE_PACKAGES" "base,linux,linux-firmware,mkinitcpio")" package_ref
}

get_required_packages() {
	local install_profile=${1:-daily}
	local -n package_ref=${2:?package reference is required}

	package_ref=()
	append_csv_packages "$(config_csv_or_default "ARCHINSTALL_REQUIRED_PACKAGES" "sudo,networkmanager,iwd,iptables-nft,dialog,make,nano,git,curl,wget,ripgrep,fd,less,man-db,man-pages")" package_ref
	append_csv_packages "$(profile_config_csv "ARCHINSTALL_REQUIRED_PACKAGES" "$install_profile" "")" package_ref
}

get_user_packages() {
	local install_profile=${1:-daily}
	local editor_choice=${2:-nano}
	local include_vscode=${3:-false}
	local custom_tools=${4:-}
	local -n package_ref=${5:?package reference is required}
	local tool_id=""

	package_ref=()

	case $install_profile in
		daily)
			append_csv_packages "$(profile_config_csv "ARCHINSTALL_USER_PACKAGES" "daily" "kate,fastfetch")" package_ref
			;;
		dev)
			append_csv_packages "$(editor_packages_csv "$editor_choice")" package_ref
			append_csv_packages "$(profile_config_csv "ARCHINSTALL_USER_PACKAGES" "dev" "fastfetch")" package_ref
			if [[ $include_vscode == "true" ]]; then
				append_csv_packages "$(config_csv_or_default "ARCHINSTALL_VSCODE_PACKAGES" "code")" package_ref
			fi
			;;
		custom)
			append_csv_packages "$(editor_packages_csv "$editor_choice")" package_ref
			# custom_tools = checklist-selected packages + user-typed extras (space-separated package names)
			if [[ -n $custom_tools ]]; then
				local _normalised_custom="${custom_tools//  / }"
				_normalised_custom="${_normalised_custom// /,}"
				append_csv_packages "$_normalised_custom" package_ref
			else
				# Fallback when no checklist result is available (e.g. state upgrade from older version)
				append_csv_packages "$(profile_config_csv "ARCHINSTALL_USER_PACKAGES" "custom" "fastfetch")" package_ref
			fi
			if [[ $include_vscode == "true" ]]; then
				append_csv_packages "$(config_csv_or_default "ARCHINSTALL_VSCODE_PACKAGES" "code")" package_ref
			fi
			;;
		*)
			return 1
			;;
	esac
}

get_final_packages() {
	local install_profile=${1:-daily}
	local editor_choice=${2:-nano}
	local include_vscode=${3:-false}
	local custom_tools=${4:-}
	local -n package_ref=${5:?package reference is required}
	local -a base_packages=()
	local -a required_packages=()
	local -a user_packages=()

	package_ref=()
	get_base_packages base_packages || return 1
	get_required_packages "$install_profile" required_packages || return 1
	get_user_packages "$install_profile" "$editor_choice" "$include_vscode" "$custom_tools" user_packages || return 1
	append_unique_packages package_ref "${base_packages[@]}"
	append_unique_packages package_ref "${required_packages[@]}"
	append_unique_packages package_ref "${user_packages[@]}"
}