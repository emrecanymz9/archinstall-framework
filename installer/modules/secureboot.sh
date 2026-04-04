#!/usr/bin/env bash

SECUREBOOT_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$SECUREBOOT_MODULE_DIR/../features/secureboot.sh" ]]; then
	# shellcheck source=installer/features/secureboot.sh
	source "$SECUREBOOT_MODULE_DIR/../features/secureboot.sh"
fi