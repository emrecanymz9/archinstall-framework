#!/usr/bin/env bash

DISPLAY_MANAGER_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$DISPLAY_MANAGER_MODULE_DIR/../desktop.sh" ]]; then
	# shellcheck source=installer/modules/desktop.sh
	source "$DISPLAY_MANAGER_MODULE_DIR/../desktop.sh"
fi
