#!/usr/bin/env bash

secure_boot_mode_label() {
	case ${1:-disabled} in
		disabled)
			printf 'Disabled\n'
			;;
		assisted)
			printf 'Assisted (sbctl)\n'
			;;
		advanced)
			printf 'Advanced (manual control)\n'
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

	menu "Secure Boot" "Choose the Secure Boot strategy.\n\nCurrent firmware state: $(secure_boot_state_label "$secure_boot_state")\n\nDisabled keeps the install unchanged. Assisted installs sbctl and prepares signed boot assets without making Secure Boot a hard requirement. Advanced keeps package support but leaves all key handling to you." 18 78 4 \
		"disabled" "Do not configure Secure Boot" \
		"assisted" "Recommended: prepare sbctl-based signing" \
		"advanced" "Manual control for preplanned Secure Boot workflows"

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
		assisted|advanced)
			package_ref+=(sbctl)
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
		assisted)
			printf 'Assisted mode installs sbctl and prepares a safe post-install Secure Boot workflow. If firmware is already enforcing Secure Boot, keep a recovery path available until keys are enrolled.'
			;;
		advanced)
			printf 'Advanced mode installs the Secure Boot tooling but leaves enrollment and signing decisions to manual follow-up.'
			;;
		*)
			printf 'Secure Boot mode: %s' "$secure_boot_mode"
			;;
	esac

	if [[ $secure_boot_state == "enabled" ]]; then
		printf '\n\nFirmware reports Secure Boot enabled. The installer will not fail hard, but you should verify your boot chain before enabling the new system for unattended use.'
	fi
}