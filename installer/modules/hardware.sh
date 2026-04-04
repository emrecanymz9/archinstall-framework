#!/usr/bin/env bash

HARDWARE_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$HARDWARE_MODULE_DIR/detect.sh" ]]; then
	# shellcheck source=installer/modules/detect.sh
	source "$HARDWARE_MODULE_DIR/detect.sh" >/dev/null 2>&1
fi

if [[ -r "$HARDWARE_MODULE_DIR/gpu/detect.sh" ]]; then
	# shellcheck source=installer/modules/gpu/detect.sh
	source "$HARDWARE_MODULE_DIR/gpu/detect.sh" >/dev/null 2>&1
fi

if [[ -r "$HARDWARE_MODULE_DIR/../features/gpu.sh" ]]; then
	# shellcheck source=installer/features/gpu.sh
	source "$HARDWARE_MODULE_DIR/../features/gpu.sh" >/dev/null 2>&1
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
		vmware|virtualbox|qemu|kvm|hyperv|vm)
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

refresh_hardware_state() {
	local cpu_vendor=""
	local gpu_vendor=""

	cpu_vendor="$(detect_cpu_vendor_safe 2>/dev/null || printf 'unknown')"
	gpu_vendor="$(detect_gpu_vendor 2>/dev/null || printf 'generic')"
	set_state "CPU_VENDOR" "$cpu_vendor" || return 1
	set_state "GPU_VENDOR" "$gpu_vendor" || return 1
	set_state "GPU_LABEL" "$(gpu_vendor_label "$gpu_vendor")" || return 1
	if type detect_environment_type >/dev/null 2>&1; then
		set_state "ENVIRONMENT_TYPE" "$(detect_environment_type 2>/dev/null || printf 'unknown')" || return 1
	fi
	if type detect_hardware_profile_json >/dev/null 2>&1; then
		set_state "HARDWARE_PROFILE_JSON" "$(detect_hardware_profile_json 2>/dev/null || printf '{}')" || return 1
	fi
	return 0
}

register_hardware_module() {
	archinstall_register_module "hardware" "Hardware detection v2" "refresh_hardware_state"
}

hardware_profile_packages() {
	local environment_vendor=${1:-baremetal}
	local gpu_vendor=${2:-unknown}
	local desktop_profile=${3:-none}
	local install_steam=${4:-false}
	local cpu_vendor=${5:-unknown}
	local environment_type=${6:-unknown}
	local -n package_ref=${7:?package reference is required}

	package_ref=()

	# CPU microcode is driven by persisted hardware state collected before strategy resolution.
	case $cpu_vendor in
		intel) package_ref+=(intel-ucode) ;;
		amd)   package_ref+=(amd-ucode) ;;
	esac

	case $environment_vendor in
		vmware)
			package_ref+=(open-vm-tools gtkmm3)
			;;
		virtualbox)
			package_ref+=(virtualbox-guest-utils)
			;;
		qemu|kvm)
			package_ref+=(spice-vdagent qemu-guest-agent)
			;;
		hyperv)
			package_ref+=(hyperv)
			;;
		*)
			;;
	esac

	# Laptop-specific optimisation packages
	if [[ $environment_type == "laptop" ]]; then
		package_ref+=(tlp acpi)
	fi

	if [[ $desktop_profile != "none" ]]; then
		gpu_driver_packages "$gpu_vendor" "$install_steam" package_ref || return 1
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
		qemu|kvm)
			service_ref+=(spice-vdagentd.service qemu-guest-agent.service)
			;;
		hyperv)
			service_ref+=(hv_fcopy_daemon.service hv_kvp_daemon.service hv_vss_daemon.service)
			;;
		*)
			;;
	esac

	local environment_type=""
	environment_type="$(get_state "ENVIRONMENT_TYPE" 2>/dev/null || printf 'unknown')"
	if [[ $environment_type == "laptop" ]]; then
		service_ref+=(tlp.service acpid.service)
	fi

	if [[ $desktop_profile != "none" ]]; then
		service_ref+=(bluetooth.service)
	fi
}