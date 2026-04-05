#!/usr/bin/env bash

detect_text_matches() {
	local haystack=${1-}
	local pattern=${2-}

	[[ -n $haystack && -n $pattern ]] || return 1
	printf '%s\n' "$haystack" | grep -qiE "$pattern" >/dev/null 2>&1
}

resolve_disk_device() {
	local device=${1:?block device is required}
	local device_name=""
	local parent_name=""

	device_name="$(basename "$device")"
	if [[ -d /sys/block/$device_name ]]; then
		printf '%s\n' "$device"
		return 0
	fi

	parent_name="$(lsblk -no pkname "$device" 2>/dev/null | head -n 1 || true)"
	parent_name="${parent_name//[[:space:]]/}"
	if [[ -n $parent_name && -d /sys/block/$parent_name ]]; then
		printf '/dev/%s\n' "$parent_name"
		return 0
	fi

	printf '%s\n' "$device"
}

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

disk_transport_value() {
	local disk=${1:?disk is required}
	local disk_name=""
	local transport=""
	local sys_transport_path=""

	transport="$(lsblk -dnro TRAN "$disk" 2>/dev/null | head -n 1 || true)"
	transport="$(printf '%s' "$transport" | sed 's/^ *//;s/ *$//')"
	if [[ -n $transport ]]; then
		printf '%s\n' "${transport,,}"
		return 0
	fi

	disk_name="$(basename "$disk")"
	if [[ ! -d /sys/block/$disk_name ]]; then
		disk_name="$(lsblk -no pkname "$disk" 2>/dev/null | head -n 1 || true)"
	fi
	case $disk_name in
		nvme*)
			printf 'nvme\n'
			return 0
			;;
		vd*|xvd*)
			printf 'virtio\n'
			return 0
			;;
		mmcblk*)
			printf 'emmc\n'
			return 0
			;;
	esac

	sys_transport_path="/sys/block/$disk_name/device/transport"
	if [[ -r $sys_transport_path ]]; then
		read -r transport < "$sys_transport_path" || true
		transport="$(printf '%s' "$transport" | sed 's/^ *//;s/ *$//')"
		if [[ -n $transport ]]; then
			printf '%s\n' "${transport,,}"
			return 0
		fi
	fi

	printf 'unknown\n'
}

disk_transport_label() {
	case ${1:-unknown} in
		nvme)
			printf 'NVMe\n'
			;;
		sata|ata)
			printf 'SATA\n'
			;;
		usb)
			printf 'USB\n'
			;;
		scsi)
			printf 'SCSI\n'
			;;
		virtio)
			printf 'VirtIO\n'
			;;
		emmc)
			printf 'eMMC\n'
			;;
		vm)
			printf 'VM\n'
			;;
		*)
			printf 'Unknown bus\n'
			;;
	esac
}

disk_rotational_value() {
	local disk=${1:?disk is required}
	local resolved_disk=""
	local disk_name=""
	local rotational_path=""
	local rotational_value=""

	resolved_disk="$(resolve_disk_device "$disk")"
	disk_name="$(basename "$resolved_disk")"
	rotational_path="/sys/block/$disk_name/queue/rotational"

	if [[ -r $rotational_path ]]; then
		read -r rotational_value < "$rotational_path" || true
		rotational_value="${rotational_value//[[:space:]]/}"
		if [[ $rotational_value == "0" || $rotational_value == "1" ]]; then
			printf '%s\n' "$rotational_value"
			return 0
		fi
	fi

	rotational_value="$(lsblk -dn -o ROTA "$resolved_disk" 2>/dev/null | head -n 1 || true)"
	rotational_value="${rotational_value//[[:space:]]/}"
	if [[ $rotational_value == "0" || $rotational_value == "1" ]]; then
		printf '%s\n' "$rotational_value"
		return 0
	fi

	return 1
}

detect_disk_type() {
	local disk=${1:?disk is required}
	local resolved_disk=""
	local disk_name=""
	local transport=""
	local model=""
	local rotational_value=""

	resolved_disk="$(resolve_disk_device "$disk")"
	disk_name="$(basename "$resolved_disk")"
	transport="$(disk_transport_value "$resolved_disk" 2>/dev/null || printf 'unknown')"
	model="$(disk_model_value "$resolved_disk" 2>/dev/null || printf '')"

	if [[ $disk_name == nvme* || $transport == "nvme" ]]; then
		printf 'nvme\n'
		return 0
	fi

	if [[ $transport == "virtio" ]] || detect_text_matches "$disk_name $model" 'vmware|virtualbox|qemu|kvm|hyper-v|hyperv|virtio'; then
		printf 'vm\n'
		return 0
	fi

	if rotational_value="$(disk_rotational_value "$resolved_disk" 2>/dev/null || true)"; then
		case $rotational_value in
			0)
				printf 'ssd\n'
				return 0
				;;
			1)
				printf 'hdd\n'
				return 0
				;;
		esac
	fi

	case $transport in
		emmc)
			printf 'ssd\n'
			;;
		nvme)
			printf 'nvme\n'
			;;
		virtio)
			printf 'vm\n'
			;;
		*)
			printf 'hdd\n'
			;;
	esac
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
	local combined_text=""

	if command -v systemd-detect-virt >/dev/null 2>&1; then
		detected="$(systemd-detect-virt 2>/dev/null || true)"
	fi
	if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
		read -r dmi_vendor < /sys/class/dmi/id/sys_vendor || true
	fi
	if [[ -r /sys/class/dmi/id/product_name ]]; then
		read -r dmi_product < /sys/class/dmi/id/product_name || true
	fi
	combined_text="$(printf '%s\n%s\n%s\n' "$detected" "$dmi_vendor" "$dmi_product")"

	if detect_text_matches "$combined_text" 'vmware'; then
		printf 'vmware\n'
		return 0
	fi
	if detect_text_matches "$combined_text" 'virtualbox|oracle|innotek'; then
		printf 'virtualbox\n'
		return 0
	fi
	if detect_text_matches "$combined_text" 'kvm|qemu'; then
		printf 'kvm\n'
		return 0
	fi
	if detect_text_matches "$combined_text" 'hyperv|hyper-v|microsoft|virtual machine'; then
		printf 'hyperv\n'
		return 0
	fi

	if [[ -n $detected || -n $dmi_vendor || -n $dmi_product ]]; then
		printf 'baremetal\n'
		return 0
	fi

	printf 'unknown\n'
}

detect_environment_type() {
	local environment_vendor=""
	local chassis_type=""

	environment_vendor="$(detect_environment_vendor_safe)"
	case $environment_vendor in
		vmware|virtualbox|kvm|hyperv)
			printf 'vm\n'
			return 0
			;;
		unknown)
			printf 'unknown\n'
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
		vmware|virtualbox|kvm|hyperv)
			printf 'vm\n'
			return 0
			;;
	esac

	if ! command -v lspci >/dev/null 2>&1; then
		printf 'generic\n'
		return 0
	fi

	lspci_output="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
	if [[ -z $lspci_output ]]; then
		printf 'generic\n'
		return 0
	fi

	if detect_text_matches "$lspci_output" 'nvidia'; then
		printf 'nvidia\n'
		return 0
	fi
	if detect_text_matches "$lspci_output" 'amd|advanced micro devices|ati'; then
		printf 'amd\n'
		return 0
	fi
	if detect_text_matches "$lspci_output" 'intel'; then
		printf 'intel\n'
		return 0
	fi

	printf 'generic\n'
}

detect_cpu_vendor_safe() {
	local cpuinfo=""

	if [[ -r /proc/cpuinfo ]]; then
		cpuinfo="$(grep -m1 'vendor_id\|model name' /proc/cpuinfo 2>/dev/null || true)"
	fi

	if detect_text_matches "$cpuinfo" 'genuineintel|intel'; then
		printf 'intel\n'
		return 0
	fi
	if detect_text_matches "$cpuinfo" 'authenticamd|amd'; then
		printf 'amd\n'
		return 0
	fi

	printf 'unknown\n'
}

detect_hardware_profile_json() {
	local cpu_vendor="$(detect_cpu_vendor_safe)"
	local gpu_vendor="$(detect_gpu_vendor_safe)"
	local environment_type="$(detect_environment_type)"

	printf '{"cpu":"%s","gpu":"%s","type":"%s"}\n' "$cpu_vendor" "$gpu_vendor" "$environment_type"
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

detect_network_status() {
	local default_route=""
	local iface=""
	local ip_addr=""
	local connection_type="Ethernet"

	default_route="$(ip route show default 2>/dev/null | head -n1 || true)"
	if [[ -z $default_route ]]; then
		printf 'Not Connected\n'
		return 0
	fi

	iface="$(printf '%s' "$default_route" | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' 2>/dev/null | head -n1 || true)"

	if [[ -n $iface ]]; then
		if [[ -d /sys/class/net/${iface}/wireless ]] || [[ -L /sys/class/net/${iface}/phy80211 ]]; then
			connection_type="WiFi"
		fi
		ip_addr="$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1 || true)"
	fi

	if [[ -n $ip_addr ]]; then
		printf 'Connected (%s) — %s\n' "$connection_type" "$ip_addr"
	else
		printf 'Connected (%s)\n' "$connection_type"
	fi
}