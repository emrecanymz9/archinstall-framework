#!/usr/bin/env bash

ARCHINSTALL_STATE_FILE=${ARCHINSTALL_STATE_FILE:-/tmp/archinstall_state}

STATE_BOOT_MODE=BOOT_MODE
STATE_GPU=GPU_VENDOR
STATE_DISK=DISK
STATE_ENVIRONMENT=ENVIRONMENT_VENDOR
STATE_FILESYSTEM=FILESYSTEM
STATE_PROFILE=INSTALL_PROFILE

ensure_state_file() {
	mkdir -p "$(dirname "$ARCHINSTALL_STATE_FILE")"
	touch "$ARCHINSTALL_STATE_FILE"
}

set_state() {
	local key=${1:?state key is required}
	local value=${2-}
	local temp_file

	ensure_state_file
	temp_file="$(mktemp "${ARCHINSTALL_STATE_FILE}.XXXXXX")" || return 1

	awk -F '\t' -v key="$key" -v value="$value" '
		BEGIN { updated = 0 }
		$1 == key {
			print key "\t" value
			updated = 1
			next
		}
		{ print }
		END {
			if (!updated) {
				print key "\t" value
			}
		}
	' "$ARCHINSTALL_STATE_FILE" > "$temp_file" || {
		rm -f "$temp_file"
		return 1
	}

	mv "$temp_file" "$ARCHINSTALL_STATE_FILE"
	if declare -F sync_install_config_json >/dev/null 2>&1; then
		sync_install_config_json >/dev/null 2>&1 || true
	fi
}

get_state() {
	local key=${1:?state key is required}

	ensure_state_file
	awk -F '\t' -v key="$key" '
		$1 == key {
			line = $0
			sub(/^[^\t]*\t/, "", line)
			print line
			found = 1
			exit
		}
		END {
			if (!found) {
				exit 1
			}
		}
	' "$ARCHINSTALL_STATE_FILE"
}

unset_state() {
	local key=${1:?state key is required}
	local temp_file

	ensure_state_file
	temp_file="$(mktemp "${ARCHINSTALL_STATE_FILE}.XXXXXX")" || return 1

	awk -F '\t' -v key="$key" '$1 != key { print }' "$ARCHINSTALL_STATE_FILE" > "$temp_file" || {
		rm -f "$temp_file"
		return 1
	}

	mv "$temp_file" "$ARCHINSTALL_STATE_FILE"
	if declare -F sync_install_config_json >/dev/null 2>&1; then
		sync_install_config_json >/dev/null 2>&1 || true
	fi
}

has_state() {
	local key=${1:?state key is required}

	get_state "$key" >/dev/null 2>&1
}

clear_state() {
	: > "$ARCHINSTALL_STATE_FILE"
	if declare -F sync_install_config_json >/dev/null 2>&1; then
		sync_install_config_json >/dev/null 2>&1 || true
	fi
}

state_get_or_default() {
	local key=${1:?state key is required}
	local default_value=${2-}
	local value=""

	value="$(get_state "$key" 2>/dev/null || true)"
	if [[ -n $value ]]; then
		printf '%s\n' "$value"
		return 0
	fi

	printf '%s\n' "$default_value"
}