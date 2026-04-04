#!/usr/bin/env bash

GPU_DRIVER_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$GPU_DRIVER_MODULE_DIR/../hardware.sh" ]]; then
	# shellcheck source=installer/modules/hardware.sh
	source "$GPU_DRIVER_MODULE_DIR/../hardware.sh"
fi
