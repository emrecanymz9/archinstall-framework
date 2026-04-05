#!/usr/bin/env bash

if [[ -r "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../core/gpu/detect.sh" ]]; then
	# shellcheck source=installer/core/gpu/detect.sh
	source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../core/gpu/detect.sh"
fi

gpu_driver_packages() {
	local gpu_vendor=${1:-generic}
	local install_steam=${2:-false}
	local -n package_ref=${3:?package reference is required}

	package_ref=()
	case $gpu_vendor in
		nvidia)
			package_ref+=(nvidia nvidia-utils)
			if [[ $install_steam == "true" ]]; then
				package_ref+=(lib32-nvidia-utils)
			fi
			;;
		intel)
			package_ref+=(mesa vulkan-intel intel-media-driver)
			if [[ $install_steam == "true" ]]; then
				package_ref+=(lib32-mesa lib32-vulkan-intel)
			fi
			;;
		amd)
			package_ref+=(mesa vulkan-radeon libva-mesa-driver)
			if [[ $install_steam == "true" ]]; then
				package_ref+=(lib32-mesa lib32-vulkan-radeon)
			fi
			;;
		generic|vm|vmware|virtualbox|qemu|kvm|hyperv)
			package_ref+=(mesa)
			if [[ $install_steam == "true" ]]; then
				package_ref+=(lib32-mesa)
			fi
			;;
		*)
			;;
	esac
}

refresh_gpu_install_state() {
	local gpu_vendor=""

	if type detect_gpu_vendor >/dev/null 2>&1; then
		gpu_vendor="$(detect_gpu_vendor 2>/dev/null || printf 'generic')"
	else
		gpu_vendor="generic"
	fi

	gpu_vendor="${gpu_vendor:-generic}"
	set_state "GPU_VENDOR" "$gpu_vendor" || return 1
	if type gpu_vendor_label >/dev/null 2>&1; then
		set_state "GPU_LABEL" "$(gpu_vendor_label "$gpu_vendor")" || return 1
	fi
	printf '%s\n' "$gpu_vendor"
}