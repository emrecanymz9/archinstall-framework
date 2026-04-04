#!/usr/bin/env bash

SYSTEM_RUNTIME_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$SYSTEM_RUNTIME_MODULE_DIR/../system.sh" ]]; then
	# shellcheck source=installer/modules/system.sh
	source "$SYSTEM_RUNTIME_MODULE_DIR/../system.sh"
fi
