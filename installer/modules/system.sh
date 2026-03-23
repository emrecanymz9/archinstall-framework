#!/usr/bin/env bash

SYSTEM_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$SYSTEM_MODULE_DIR/detect.sh" ]]; then
	# shellcheck source=installer/modules/detect.sh
	source "$SYSTEM_MODULE_DIR/detect.sh"
fi

ARCHINSTALL_EFI_GLOBAL_GUID=${ARCHINSTALL_EFI_GLOBAL_GUID:-8be4df61-93ca-11d2-aa0d-00e098032b8c}

runtime_state_or_default() {
	local key=${1:?state key is required}
	local default_value=${2-}
	local value=""

	if type get_state >/dev/null 2>&1; then
		value="$(get_state "$key" 2>/dev/null || true)"
		if [[ -n $value ]]; then
			printf '%s\n' "$value"
			return 0
		fi
	fi

	printf '%s\n' "$default_value"
}

read_efi_variable_flag() {
	local variable_name=${1:?EFI variable name is required}
	local variable_path="/sys/firmware/efi/efivars/${variable_name}-${ARCHINSTALL_EFI_GLOBAL_GUID}"
	local value=""

	if [[ ! -r $variable_path ]]; then
		return 1
	fi

	value="$(od -An -t u1 -j 4 -N 1 "$variable_path" 2>/dev/null | awk 'NR == 1 { print $1 }' || true)"
	if [[ -z $value ]]; then
		return 1
	fi

	printf '%s\n' "$value"
}

detect_secure_boot_state() {
	local boot_mode=${1:-$(detect_boot_mode 2>/dev/null || printf 'bios')}
	local secure_boot_flag=""

	if [[ $boot_mode != "uefi" ]]; then
		printf 'unsupported\n'
		return 0
	fi

	secure_boot_flag="$(read_efi_variable_flag SecureBoot || true)"
	case $secure_boot_flag in
		1)
			printf 'enabled\n'
			;;
		0)
			printf 'disabled\n'
			;;
		*)
			printf 'unknown\n'
			;;
	esac
}

detect_secure_boot_setup_mode() {
	local boot_mode=${1:-$(detect_boot_mode 2>/dev/null || printf 'bios')}
	local setup_mode_flag=""

	if [[ $boot_mode != "uefi" ]]; then
		printf 'unsupported\n'
		return 0
	fi

	setup_mode_flag="$(read_efi_variable_flag SetupMode || true)"
	case $setup_mode_flag in
		1)
			printf 'setup\n'
			;;
		0)
			printf 'user\n'
			;;
		*)
			printf 'unknown\n'
			;;
	esac
}

normalize_virtualization_vendor() {
	case ${1:-baremetal} in
		vmware)
			printf 'vmware\n'
			;;
		oracle|virtualbox)
			printf 'virtualbox\n'
			;;
		qemu|kvm)
			printf 'qemu\n'
			;;
		hyperv|microsoft)
			printf 'hyperv\n'
			;;
		xen)
			printf 'xen\n'
			;;
		none|""|baremetal)
			printf 'baremetal\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

detect_virtualization_vendor() {
	if type detect_environment_vendor_safe >/dev/null 2>&1; then
		detect_environment_vendor_safe
		return 0
	fi

	printf 'baremetal\n'
}

environment_label() {
	case ${1:-baremetal} in
		vmware)
			printf 'VMware Virtual Machine\n'
			;;
		virtualbox)
			printf 'VirtualBox Virtual Machine\n'
			;;
		qemu)
			printf 'QEMU/KVM Virtual Machine\n'
			;;
		hyperv)
			printf 'Microsoft Hyper-V Virtual Machine\n'
			;;
		xen)
			printf 'Xen Virtual Machine\n'
			;;
		baremetal)
			printf 'Bare Metal\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

secure_boot_state_label() {
	case ${1:-unknown} in
		enabled)
			printf 'Enabled\n'
			;;
		disabled)
			printf 'Disabled\n'
			;;
		unsupported)
			printf 'Not Supported\n'
			;;
		unknown)
			printf 'Unavailable\n'
			;;
		*)
			printf 'Unavailable\n'
			;;
	esac
}

boot_mode_status_label() {
	local boot_mode=${1:-bios}
	local secure_boot_state=${2:-unsupported}

	case $boot_mode in
		uefi)
			printf 'UEFI (Secure Boot: %s)\n' "$(secure_boot_state_label "$secure_boot_state")"
			;;
		bios)
			printf 'BIOS (Secure Boot: Not Supported)\n'
			;;
		*)
			printf 'BIOS (Secure Boot: Not Supported)\n'
			;;
	esac
}

refresh_runtime_system_state() {
	local boot_mode=""
	local secure_boot_state=""
	local secure_boot_setup_mode=""
	local environment_vendor=""
	local environment_type=""

	if type detect_boot_mode_safe >/dev/null 2>&1; then
		boot_mode="$(detect_boot_mode_safe)"
	else
		boot_mode="$(detect_boot_mode 2>/dev/null || printf 'bios')"
	fi
	secure_boot_state="$(detect_secure_boot_state "$boot_mode")"
	secure_boot_setup_mode="$(detect_secure_boot_setup_mode "$boot_mode")"
	environment_vendor="$(detect_virtualization_vendor)"
	if type detect_environment_type >/dev/null 2>&1; then
		environment_type="$(detect_environment_type)"
	else
		environment_type="desktop"
	fi

	set_state "BOOT_MODE" "$boot_mode" || return 1
	set_state "CURRENT_SECURE_BOOT_STATE" "$secure_boot_state" || return 1
	set_state "CURRENT_SECURE_BOOT_SETUP_MODE" "$secure_boot_setup_mode" || return 1
	set_state "ENVIRONMENT_VENDOR" "$environment_vendor" || return 1
	set_state "ENVIRONMENT_LABEL" "$(environment_label "$environment_vendor")" || return 1
	set_state "ENVIRONMENT_TYPE" "$environment_type" || return 1
	return 0
}

runtime_boot_summary() {
	local boot_mode=""
	local secure_boot_state=""

	boot_mode="$(runtime_state_or_default "BOOT_MODE" "bios")"
	secure_boot_state="$(runtime_state_or_default "CURRENT_SECURE_BOOT_STATE" "unsupported")"
	boot_mode_status_label "$boot_mode" "$secure_boot_state"
}

runtime_environment_summary() {
	local environment_vendor=""

	environment_vendor="$(runtime_state_or_default "ENVIRONMENT_VENDOR" "baremetal")"
	environment_label "$environment_vendor"
}