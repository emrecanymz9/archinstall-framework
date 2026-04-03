#!/usr/bin/env bash

STATE_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -r "$STATE_MODULE_DIR/state.sh" ]]; then
	# shellcheck disable=SC1090
	source "$STATE_MODULE_DIR/state.sh"
	return 0 2>/dev/null || exit 0
fi

printf '[WARN] Missing canonical state module: %s/state.sh\n' "$STATE_MODULE_DIR" >&2