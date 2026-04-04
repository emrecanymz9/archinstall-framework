#!/usr/bin/env bash

secure_boot_mode_label() {
	case ${1:-disabled} in
		disabled)
			printf 'Disabled\n'
			;;
		setup)
			printf 'Setup Foundation\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

select_secure_boot_mode() {
	local current_mode=${1:-disabled}
	local boot_mode=${2:-bios}
	local secure_boot_state=${3:-unsupported}

	if [[ $boot_mode != "uefi" ]]; then
		printf 'disabled\n'
		return 0
	fi

	menu "Secure Boot" "Choose the Secure Boot strategy.\n\nCurrent firmware state: $(secure_boot_state_label "$secure_boot_state")\n\nDisabled leaves the boot chain unchanged. Setup foundation installs sbctl and ukify, prepares UKIs, and attempts safe enrollment only when firmware setup mode permits it." 18 78 4 \
		"disabled" "Do not configure Secure Boot" \
		"setup" "Prepare a non-fatal sbctl-based Secure Boot foundation"

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

secure_boot_packages() {
	local secure_boot_mode=${1:-disabled}
	local boot_mode=${2:-bios}
	local -n package_ref=${3:?package reference is required}

	package_ref=()
	if [[ $boot_mode != "uefi" ]]; then
		return 0
	fi

	case $secure_boot_mode in
		setup)
			package_ref+=(sbctl systemd-ukify)
			;;
		*)
			;;
	esac
}

secure_boot_guidance_text() {
	local secure_boot_mode=${1:-disabled}
	local boot_mode=${2:-bios}
	local secure_boot_state=${3:-unsupported}

	if [[ $boot_mode != "uefi" ]]; then
		printf 'Secure Boot is not available in BIOS mode.'
		return 0
	fi

	case $secure_boot_mode in
		disabled)
			printf 'Secure Boot configuration is disabled.'
			;;
		setup)
			printf 'Setup foundation mode installs sbctl and systemd-ukify, prepares a UKI workflow, and keeps key enrollment best-effort so the install remains bootable even when firmware ownership is not ready.'
			;;
		*)
			printf 'Secure Boot mode: %s' "$secure_boot_mode"
			;;
	esac

	if [[ $secure_boot_state == "enabled" ]]; then
		printf '\n\nFirmware reports Secure Boot enabled. The installer will not fail hard, but you should verify your boot chain before enabling the new system for unattended use.'
	fi
}