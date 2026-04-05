#!/usr/bin/env bash

ARCHINSTALL_STATE_FILE=${ARCHINSTALL_STATE_FILE:-/tmp/archinstall_state}

STATE_BOOT_MODE=BOOT_MODE
STATE_GPU=GPU_VENDOR
STATE_DISK=DISK
STATE_ENVIRONMENT=ENVIRONMENT_VENDOR
STATE_FILESYSTEM=FILESYSTEM
STATE_PROFILE=INSTALL_PROFILE

normalize_boolean_state() {
	case ${1:-false} in
		1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
			printf 'true\n'
			;;
		*)
			printf 'false\n'
			;;
	esac
}

normalize_bootloader_state() {
	local value=${1:-}
	local boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || printf 'bios')"

	case $value in
		systemd-boot|grub|limine)
			;;
		*)
			if [[ $boot_mode == "uefi" ]]; then
				printf 'systemd-boot\n'
			else
				printf 'grub\n'
			fi
			return 0
			;;
	esac

	if [[ $boot_mode != "uefi" && $value == "systemd-boot" ]]; then
		printf 'grub\n'
		return 0
	fi

	printf '%s\n' "$value"
}

normalize_display_manager() {
	case ${1:-sddm} in
		sddm|greetd|none)
			printf '%s\n' "$1"
			;;
		*)
			printf 'sddm\n'
			;;
	esac
}

normalize_greeter() {
	case ${1:-none} in
		none|tuigreet|qtgreet)
			printf '%s\n' "$1"
			;;
		*)
			printf 'none\n'
			;;
	esac
}

normalize_snapshot_provider() {
	case ${1:-none} in
		none|snapper)
			printf '%s\n' "$1"
			;;
		*)
			printf 'none\n'
			;;
	esac
}

normalize_secure_boot_mode() {
	case ${1:-disabled} in
		disabled|setup)
			printf '%s\n' "$1"
			;;
		*)
			printf 'disabled\n'
			;;
	esac
}

normalize_display_session() {
	case ${1:-wayland} in
		wayland|x11)
			printf '%s\n' "$1"
			;;
		*)
			printf 'wayland\n'
			;;
	esac
}

normalize_disk_type() {
	local value=${1-}
	local normalized=""

	value="${value//$'\r'/}"
	value="${value//$'\n'/}"
	normalized="${value,,}"
	normalized="${normalized//[[:space:]_-]/}"

	case $normalized in
		vm|virtio|virtual|virtualmachine|vmware|virtualbox|qemu|kvm|hyperv)
			printf 'vm\n'
			;;
		""|auto|unknown)
			printf 'hdd\n'
			;;
		hdd|rotational)
			printf 'hdd\n'
			;;
		ssd|sata|satassd|ata|flash|emmc|mmc|mmcblk)
			printf 'ssd\n'
			;;
		nvme|nvmessd|pcie)
			printf 'nvme\n'
			;;
		*)
			printf 'hdd\n'
			;;
	esac
}

disk_type_label() {
	case "$(normalize_disk_type "${1-unknown}")" in
		hdd)
			printf 'HDD\n'
			;;
		ssd)
			printf 'SATA SSD\n'
			;;
		nvme)
			printf 'NVMe SSD\n'
			;;
		vm)
			printf 'VM Disk\n'
			;;
		*)
			printf 'HDD\n'
			;;
	esac
}

ensure_state_file() {
	mkdir -p "$(dirname "$ARCHINSTALL_STATE_FILE")"
	touch "$ARCHINSTALL_STATE_FILE"
}

set_state() {
	local key=${1:?state key is required}
	local value=${2-}
	local temp_file

	case $key in
		DISK_TYPE)
			value="$(normalize_disk_type "$value")"
			;;
		DISPLAY_MANAGER)
			value="$(normalize_display_manager "$value")"
			;;
		GREETER)
			value="$(normalize_greeter "$value")"
			;;
		DISPLAY_SESSION)
			value="$(normalize_display_session "$value")"
			;;
		SNAPSHOT_PROVIDER)
			value="$(normalize_snapshot_provider "$value")"
			;;
		SECURE_BOOT_MODE)
			value="$(normalize_secure_boot_mode "$value")"
			;;
		BOOTLOADER)
			value="$(normalize_bootloader_state "$value")"
			;;
		INSTALL_STEAM)
			value="$(normalize_boolean_state "$value")"
			;;
	esac

	ensure_state_file
	temp_file="$(mktemp "${ARCHINSTALL_STATE_FILE}.XXXXXX")" || return 1

	awk -F '\t' -v key="$key" -v value="$value" '
		BEGIN { updated = 0 }
		$1 == key {
			print key "\t" value
			updated = 1
			next
		}
		{ print }
		END {
			if (!updated) {
				print key "\t" value
			}
		}
	' "$ARCHINSTALL_STATE_FILE" > "$temp_file" || {
		rm -f "$temp_file"
		return 1
	}

	mv "$temp_file" "$ARCHINSTALL_STATE_FILE"
	if declare -F sync_install_config_json >/dev/null 2>&1; then
		sync_install_config_json >/dev/null 2>&1 || true
	fi
}

get_state() {
	local key=${1:?state key is required}

	ensure_state_file
	if awk -F '\t' -v key="$key" '
		$1 == key {
			line = $0
			sub(/^[^\t]*\t/, "", line)
			print line
			found = 1
			exit
		}
		END {
			if (!found) {
				exit 1
			}
		}
	' "$ARCHINSTALL_STATE_FILE"; then
		return 0
	fi

	return 1
}

unset_state() {
	local key=${1:?state key is required}
	local temp_file

	ensure_state_file
	temp_file="$(mktemp "${ARCHINSTALL_STATE_FILE}.XXXXXX")" || return 1

	awk -F '\t' -v key="$key" '$1 != key { print }' "$ARCHINSTALL_STATE_FILE" > "$temp_file" || {
		rm -f "$temp_file"
		return 1
	}

	mv "$temp_file" "$ARCHINSTALL_STATE_FILE"
	if declare -F sync_install_config_json >/dev/null 2>&1; then
		sync_install_config_json >/dev/null 2>&1 || true
	fi
}

has_state() {
	local key=${1:?state key is required}

	get_state "$key" >/dev/null 2>&1
}

clear_state() {
	: > "$ARCHINSTALL_STATE_FILE"
	if declare -F sync_install_config_json >/dev/null 2>&1; then
		sync_install_config_json >/dev/null 2>&1 || true
	fi
}

state_get_or_default() {
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