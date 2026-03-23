#!/usr/bin/env bash

STATE_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$STATE_MODULE_DIR/core/state.sh" ]]; then
	# shellcheck disable=SC1090
	source "$STATE_MODULE_DIR/core/state.sh"
	return 0 2>/dev/null || exit 0
fi

printf '[WARN] Missing core state module: %s/core/state.sh\n' "$STATE_MODULE_DIR" >&2