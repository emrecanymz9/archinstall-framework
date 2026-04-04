#!/usr/bin/env bash

SNAPSHOTS_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$SNAPSHOTS_MODULE_DIR/../features/snapshots.sh" ]]; then
	# shellcheck source=installer/features/snapshots.sh
	source "$SNAPSHOTS_MODULE_DIR/../features/snapshots.sh"
fi