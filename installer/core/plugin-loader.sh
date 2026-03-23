#!/usr/bin/env bash

PLUGIN_LOADER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT_DIR="$(cd -- "$PLUGIN_LOADER_DIR/.." && pwd)/plugins"

load_installer_plugins() {
	local plugin_file=""
	local plugin_dir=""
	local plugin_name=""

	if [[ ! -d $PLUGIN_ROOT_DIR ]]; then
		return 0
	fi

	while IFS= read -r plugin_file; do
		[[ -n $plugin_file ]] || continue
		plugin_dir="$(dirname "$plugin_file")"
		plugin_name="$(basename "$plugin_dir")"
		if ! bash -n "$plugin_file" >/dev/null 2>&1; then
			if declare -F log_debug >/dev/null 2>&1; then
				log_debug "Skipping plugin with syntax errors: $plugin_name"
			else
				printf '[WARN] Skipping plugin with syntax errors: %s\n' "$plugin_name" >&2
			fi
			continue
		fi
		# shellcheck disable=SC1090
		if source "$plugin_file"; then
			if declare -F log_debug >/dev/null 2>&1; then
				log_debug "Plugin loaded successfully: $plugin_name"
			fi
		else
			if declare -F log_debug >/dev/null 2>&1; then
				log_debug "Plugin load failed: $plugin_name"
			else
				printf '[WARN] Plugin load failed: %s\n' "$plugin_name" >&2
			fi
		fi
	done < <(find "$PLUGIN_ROOT_DIR" -mindepth 2 -maxdepth 2 -type f -name plugin.sh 2>/dev/null | sort)
}