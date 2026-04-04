#!/usr/bin/env bash

NETWORK_SERVICES_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$NETWORK_SERVICES_MODULE_DIR/../system/network.sh" ]]; then
	# shellcheck source=installer/modules/system/network.sh
	source "$NETWORK_SERVICES_MODULE_DIR/../system/network.sh"
fi
