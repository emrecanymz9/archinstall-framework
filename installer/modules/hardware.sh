#!/usr/bin/env bash

HARDWARE_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$HARDWARE_MODULE_DIR/detect.sh" ]]; then
	# shellcheck source=installer/modules/detect.sh
	source "$HARDWARE_MODULE_DIR/detect.sh"
fi

gpu_vendor_label() {
	case ${1:-unknown} in
		intel)
			printf 'Intel\n'
			;;
		amd)
			printf 'AMD\n'
			;;
		nvidia)
			printf 'NVIDIA\n'
			;;
		vmware|virtualbox|qemu|hyperv|xen)
			printf 'VM\n'
			;;
		none)
			printf 'Generic\n'
			;;
		unknown)
			printf 'Generic\n'
			;;
		generic)
			printf 'Generic\n'
			;;
		*)
			printf 'Generic\n'
			;;
	esac
}

detect_gpu_vendor() {
	if type detect_gpu_vendor_safe >/dev/null 2>&1; then
		detect_gpu_vendor_safe
		return 0
	fi

	printf 'generic\n'
}

refresh_hardware_state() {
	local gpu_vendor=""

	gpu_vendor="$(detect_gpu_vendor)"
	set_state "GPU_VENDOR" "$gpu_vendor" || return 1
	set_state "GPU_LABEL" "$(gpu_vendor_label "$gpu_vendor")" || return 1
	return 0
}

hardware_profile_packages() {
	local environment_vendor=${1:-baremetal}
	local gpu_vendor=${2:-unknown}
	local desktop_profile=${3:-none}
	local -n package_ref=${4:?package reference is required}

	package_ref=()

	case $environment_vendor in
		vmware)
			package_ref+=(open-vm-tools gtkmm3)
			;;
		virtualbox)
			package_ref+=(virtualbox-guest-utils)
			;;
		qemu)
			package_ref+=(spice-vdagent qemu-guest-agent)
			;;
		*)
			;;
	esac

	if [[ $desktop_profile != "none" ]]; then
		case $gpu_vendor in
			nvidia)
				package_ref+=(nvidia nvidia-utils)
				;;
			intel|amd|generic|vmware|virtualbox|qemu|hyperv|xen)
				package_ref+=(mesa)
				;;
			*)
				;;
		esac
	fi
}

hardware_profile_services() {
	local environment_vendor=${1:-baremetal}
	local desktop_profile=${2:-none}
	local -n service_ref=${3:?service reference is required}

	service_ref=()

	case $environment_vendor in
		vmware)
			service_ref+=(vmtoolsd.service)
			;;
		virtualbox)
			service_ref+=(vboxservice.service)
			;;
		qemu)
			service_ref+=(spice-vdagentd.service qemu-guest-agent.service)
			;;
		*)
			;;
	esac

	if [[ $desktop_profile != "none" ]]; then
		service_ref+=(bluetooth.service)
	fi
}