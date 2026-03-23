#!/usr/bin/env bash

ARCHINSTALL_EFI_GLOBAL_GUID=${ARCHINSTALL_EFI_GLOBAL_GUID:-8be4df61-93ca-11d2-aa0d-00e098032b8c}

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
	local detected=""
	local dmi_vendor=""
	local dmi_product=""

	if command -v systemd-detect-virt >/dev/null 2>&1; then
		detected="$(systemd-detect-virt 2>/dev/null || true)"
	fi

	if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
		read -r dmi_vendor < /sys/class/dmi/id/sys_vendor || true
	fi
	if [[ -r /sys/class/dmi/id/product_name ]]; then
		read -r dmi_product < /sys/class/dmi/id/product_name || true
	fi

	case "${detected,,}:${dmi_vendor,,}:${dmi_product,,}" in
		vmware*|*:vmware*|*:*:vmware*)
			printf 'vmware\n'
			;;
		oracle*|virtualbox*|*:oracle*|*:innotek*|*:*:virtualbox*)
			printf 'virtualbox\n'
			;;
		qemu*|kvm*|*:qemu*|*:*:kvm*|*:*:qemu*)
			printf 'qemu\n'
			;;
		hyperv*|microsoft*|*:microsoft*|*:*:virtual machine*)
			printf 'hyperv\n'
			;;
		xen*|*:xen*|*:*:xen*)
			printf 'xen\n'
			;;
		:none:|baremetal:*|*:|*::)
			printf 'baremetal\n'
			;;
		*)
			if [[ -n $detected && $detected != none ]]; then
				normalize_virtualization_vendor "$detected"
			else
				printf 'baremetal\n'
			fi
			;;
		esac
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
			printf 'Unknown\n'
			;;
		*)
			printf '%s\n' "$1"
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
			printf '%s\n' "$boot_mode"
			;;
	esac
}

refresh_runtime_system_state() {
	local boot_mode=""
	local secure_boot_state=""
	local secure_boot_setup_mode=""
	local environment_vendor=""

	boot_mode="$(detect_boot_mode 2>/dev/null || printf 'bios')"
	secure_boot_state="$(detect_secure_boot_state "$boot_mode")"
	secure_boot_setup_mode="$(detect_secure_boot_setup_mode "$boot_mode")"
	environment_vendor="$(detect_virtualization_vendor)"

	set_state "BOOT_MODE" "$boot_mode" || return 1
	set_state "CURRENT_SECURE_BOOT_STATE" "$secure_boot_state" || return 1
	set_state "CURRENT_SECURE_BOOT_SETUP_MODE" "$secure_boot_setup_mode" || return 1
	set_state "ENVIRONMENT_VENDOR" "$environment_vendor" || return 1
	set_state "ENVIRONMENT_LABEL" "$(environment_label "$environment_vendor")" || return 1
	return 0
}

runtime_boot_summary() {
	local boot_mode=""
	local secure_boot_state=""

	boot_mode="$(state_or_default "BOOT_MODE" "bios")"
	secure_boot_state="$(state_or_default "CURRENT_SECURE_BOOT_STATE" "unsupported")"
	boot_mode_status_label "$boot_mode" "$secure_boot_state"
}

runtime_environment_summary() {
	local environment_vendor=""

	environment_vendor="$(state_or_default "ENVIRONMENT_VENDOR" "baremetal")"
	environment_label "$environment_vendor"
}