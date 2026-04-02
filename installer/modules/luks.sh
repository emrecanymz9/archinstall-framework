#!/usr/bin/env bash

luks_enabled() {
	if declare -F flag_enabled >/dev/null 2>&1; then
		flag_enabled "$(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false')"
		return $?
	fi
	[[ $(get_state "ENABLE_LUKS" 2>/dev/null || printf 'false') == "true" ]]
}

luks_mapper_name() {
	printf '%s\n' "$(get_state "LUKS_MAPPER_NAME" 2>/dev/null || printf 'cryptroot')"
}

luks_mapper_path() {
	printf '/dev/mapper/%s\n' "$(luks_mapper_name)"
}

luks_required_packages() {
	local enable_luks=${1:-false}
	local -n package_ref=${2:?package reference is required}

	package_ref=()
	if declare -F flag_enabled >/dev/null 2>&1 && flag_enabled "$enable_luks"; then
		package_ref=(cryptsetup)
	fi
}

luks_mkinitcpio_hooks() {
	if luks_enabled; then
		printf 'base udev autodetect modconf block keyboard keymap encrypt filesystems fsck\n'
		return 0
	fi

	printf 'base udev autodetect modconf block filesystems keyboard fsck\n'
}

luks_kernel_cmdline_prefix() {
	local luks_partition_uuid=${1:-}
	local mapper_name=${2:-$(luks_mapper_name)}

	if [[ -z $luks_partition_uuid ]] || ! luks_enabled; then
		printf '\n'
		return 0
	fi

	printf 'cryptdevice=UUID=%s:%s ' "$luks_partition_uuid" "$mapper_name"
}

prepare_luks_root_device() {
	local root_partition=${1:?root partition is required}
	local mapper_name=${2:-$(luks_mapper_name)}
	local luks_password=${3-}

	if [[ -z $luks_password ]]; then
		printf '[FAIL] LUKS is enabled but no encryption password was provided.\n' >&2
		return 1
	fi

	printf '%s' "$luks_password" | cryptsetup luksFormat --type luks2 --batch-mode "$root_partition" - >/dev/null 2>&1 || return 1
	printf '%s' "$luks_password" | cryptsetup open "$root_partition" "$mapper_name" - >/dev/null 2>&1 || return 1
	printf '%s\n' "/dev/mapper/$mapper_name"
}

open_luks_root_device() {
	local root_partition=${1:?root partition is required}
	local mapper_name=${2:-$(luks_mapper_name)}
	local luks_password=${3-}

	if cryptsetup status "$mapper_name" >/dev/null 2>&1; then
		printf '%s\n' "/dev/mapper/$mapper_name"
		return 0
	fi

	[[ -n $luks_password ]] || return 1
	printf '%s' "$luks_password" | cryptsetup open "$root_partition" "$mapper_name" - >/dev/null 2>&1 || return 1
	printf '%s\n' "/dev/mapper/$mapper_name"
}

close_luks_root_device() {
	local mapper_name=${1:-$(luks_mapper_name)}

	if cryptsetup status "$mapper_name" >/dev/null 2>&1; then
		cryptsetup close "$mapper_name" >/dev/null 2>&1 || return 1
	fi
}

register_luks_module() {
	archinstall_register_module "luks" "LUKS2 encryption support" "prepare_luks_root_device"
}