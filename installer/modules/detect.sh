#!/usr/bin/env bash

disk_model_value() {
	local disk=${1:?disk is required}
	local model=""
	local disk_name=""
	local vendor_path=""
	local model_path=""
	local vendor=""
	local product=""

	model="$(lsblk -dnro MODEL "$disk" 2>/dev/null | head -n 1 || true)"
	model=${model//$'\t'/ }
	model=${model//$'\n'/ }
	model="$(printf '%s' "$model" | sed 's/^ *//;s/ *$//')"
	if [[ -n $model ]]; then
		printf '%s\n' "$model"
		return 0
	fi

	disk_name="$(basename "$disk")"
	vendor_path="/sys/block/$disk_name/device/vendor"
	model_path="/sys/block/$disk_name/device/model"
	if [[ -r $vendor_path ]]; then
		read -r vendor < "$vendor_path" || true
	fi
	if [[ -r $model_path ]]; then
		read -r product < "$model_path" || true
	fi
	vendor="$(printf '%s' "$vendor" | sed 's/^ *//;s/ *$//')"
	product="$(printf '%s' "$product" | sed 's/^ *//;s/ *$//')"
	model="$(printf '%s %s' "$vendor" "$product" | sed 's/^ *//;s/ *$//')"
	if [[ -n $model ]]; then
		printf '%s\n' "$model"
		return 0
	fi

	printf 'Model not reported\n'
}

detect_boot_mode_safe() {
	if [[ -d /sys/firmware/efi ]]; then
		printf 'uefi\n'
		return 0
	fi

	printf 'bios\n'
}

detect_environment_vendor_safe() {
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
			case ${detected:-none} in
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
				*)
					printf 'baremetal\n'
					;;
			esac
			;;
	esac
}

detect_environment_type() {
	local environment_vendor=""
	local chassis_type=""

	environment_vendor="$(detect_environment_vendor_safe)"
	case $environment_vendor in
		vmware|virtualbox|qemu|hyperv|xen)
			printf 'vm\n'
			return 0
			;;
	esac

	if compgen -G '/sys/class/power_supply/BAT*' >/dev/null 2>&1; then
		printf 'laptop\n'
		return 0
	fi
	if [[ -r /sys/class/dmi/id/chassis_type ]]; then
		read -r chassis_type < /sys/class/dmi/id/chassis_type || true
		case $chassis_type in
			8|9|10|14|30|31|32)
				printf 'laptop\n'
				return 0
				;;
		esac
	fi

	printf 'desktop\n'
}

detect_gpu_vendor_safe() {
	local environment_vendor=""
	local lspci_output=""

	environment_vendor="$(detect_environment_vendor_safe)"
	case $environment_vendor in
		vmware|virtualbox|qemu|hyperv|xen)
			printf '%s\n' "$environment_vendor"
			return 0
			;;
	esac

	if ! command -v lspci >/dev/null 2>&1; then
		printf 'generic\n'
		return 0
	fi

	lspci_output="$(lspci 2>/dev/null | grep -E 'VGA|3D' || true)"
	if [[ -z $lspci_output ]]; then
		printf 'generic\n'
		return 0
	fi

	case ${lspci_output,,} in
		*"nvidia"*)
			printf 'nvidia\n'
			;;
		*"amd"*|*"advanced micro devices"*|*"ati"*)
			printf 'amd\n'
			;;
		*"intel"*)
			printf 'intel\n'
			;;
		*)
			printf 'generic\n'
			;;
	esac
}

detect_disk_os_presence() {
	local disk=${1:?disk is required}
	local has_windows="false"
	local has_linux="false"
	local fstype=""
	local partlabel=""

	while IFS=$'\t' read -r _ _ fstype partlabel; do
		case ${fstype,,}:${partlabel,,} in
			ntfs:*|*:*windows*|*:*microsoft*)
				has_windows="true"
				;;
			ext4:*|btrfs:*|xfs:*|f2fs:*|swap:*|*:*linux*)
				has_linux="true"
				;;
		esac
	done < <(lsblk -lnpo NAME,SIZE,FSTYPE,PARTLABEL "$disk" 2>/dev/null)

	if [[ $has_windows == "true" && $has_linux == "true" ]]; then
		printf 'Windows + Linux detected\n'
		return 0
	fi
	if [[ $has_windows == "true" ]]; then
		printf 'Windows detected\n'
		return 0
	fi
	if [[ $has_linux == "true" ]]; then
		printf 'Linux detected\n'
		return 0
	fi

	printf 'No OS signatures detected\n'
}