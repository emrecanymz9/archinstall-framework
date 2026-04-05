#!/usr/bin/env bash

GPU_DETECT_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$GPU_DETECT_MODULE_DIR/../detect.sh" ]]; then
	# shellcheck source=installer/core/detect.sh
	source "$GPU_DETECT_MODULE_DIR/../detect.sh"
fi

detect_gpu_vendor() {
	if type detect_gpu_vendor_safe >/dev/null 2>&1; then
		detect_gpu_vendor_safe 2>/dev/null || printf 'generic\n'
		return 0
	fi

	printf 'generic\n'
}