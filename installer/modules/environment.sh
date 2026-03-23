#!/usr/bin/env bash

ENVIRONMENT_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$ENVIRONMENT_MODULE_DIR/system.sh" ]]; then
	# shellcheck source=installer/modules/system.sh
	source "$ENVIRONMENT_MODULE_DIR/system.sh" >/dev/null 2>&1
fi

if ! type environment_label >/dev/null 2>&1; then
	environment_label() {
		printf '%s\n' "${1:-Unknown}"
	}
fi

if ! type runtime_environment_summary >/dev/null 2>&1; then
	runtime_environment_summary() {
		printf 'Unknown\n'
	}
fi

if ! type detect_virtualization_vendor >/dev/null 2>&1; then
	detect_virtualization_vendor() {
		printf 'unknown\n'
	}
fi