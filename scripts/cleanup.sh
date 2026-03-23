#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cleanup_repo_artifacts() {
	find "$REPO_ROOT" -type f \( \
		-name '*.tmp' -o \
		-name '*.bak' -o \
		-name '*.orig' -o \
		-name '*.rej' -o \
		-name '*.swp' -o \
		-name '.DS_Store' -o \
		-name 'Thumbs.db' \
	\) -print -delete 2>/dev/null || true

	find "$REPO_ROOT" -type d \( \
		-name '__pycache__' -o \
		-name '.pytest_cache' -o \
		-name '.mypy_cache' -o \
		-name '.ruff_cache' \
	\) -prune -print -exec rm -rf {} + 2>/dev/null || true
}

cleanup_runtime_logs() {
	rm -f /tmp/archinstall_state /tmp/archinstall_debug.log /tmp/archinstall_install.log /tmp/archinstall_progress.log 2>/dev/null || true
}

cleanup_repo_artifacts
cleanup_runtime_logs

printf 'Cleanup complete. Core installer files were preserved.\n'