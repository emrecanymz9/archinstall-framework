#!/usr/bin/env bash

RUNTIME_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! type detect_boot_mode >/dev/null 2>&1 && [[ -r "$RUNTIME_MODULE_DIR/bootloader.sh" ]]; then
	# shellcheck source=installer/modules/bootloader.sh
	source "$RUNTIME_MODULE_DIR/bootloader.sh"
fi

if [[ -r "$RUNTIME_MODULE_DIR/system.sh" ]]; then
	# shellcheck source=installer/modules/system.sh
	source "$RUNTIME_MODULE_DIR/system.sh"
fi

if ! type refresh_runtime_system_state >/dev/null 2>&1; then
	refresh_runtime_system_state() {
		return 0
	}
fi

if ! type runtime_boot_summary >/dev/null 2>&1; then
	runtime_boot_summary() {
		printf 'Unknown\n'
	}
fi

if ! type boot_mode_status_label >/dev/null 2>&1; then
	boot_mode_status_label() {
		printf '%s\n' "${1:-Unknown}"
	}
fi

if ! type secure_boot_state_label >/dev/null 2>&1; then
	secure_boot_state_label() {
		printf '%s\n' "${1:-Unknown}"
	}
fi