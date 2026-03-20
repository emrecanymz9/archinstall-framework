#!/usr/bin/env bash

ARCHINSTALL_STATE_FILE=${ARCHINSTALL_STATE_FILE:-/tmp/archinstall_state}

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
}

has_state() {
	local key=${1:?state key is required}

	get_state "$key" >/dev/null 2>&1
}

clear_state() {
	: > "$ARCHINSTALL_STATE_FILE"
}