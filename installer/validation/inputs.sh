#!/usr/bin/env bash

prompt_required_input() {
	local title=${1:?title is required}
	local prompt=${2:?prompt is required}
	local initial_value=${3-}
	local value=""
	local status=0
	local dialog_body=""
	local validation_error=""

	while true; do
		dialog_body="$prompt"
		if [[ -n $validation_error ]]; then
			dialog_body+="\n\nError: $validation_error"
		fi

		input_box "$title" "$dialog_body" "$initial_value" 12 76
		value="$DIALOG_RESULT"
		status=$DIALOG_STATUS
		case $status in
			0)
				if [[ -n $value ]]; then
					printf '%s\n' "$value"
					return 0
				fi
				validation_error="A value is required."
				;;
			1|255)
				return 1
				;;
			*)
				return 1
				;;
		esac
		initial_value="$value"
	done
}

prompt_username() {
	local title=${1:-"Username"}
	local initial_value=${2:-"archuser"}
	local value=""
	local status=0
	local dialog_body=""
	local validation_error=""

	while true; do
		dialog_body="Create the primary user account.\n\nConstraints:\n- must start with a lowercase letter or underscore\n- allowed: lowercase letters, digits, underscores, hyphens\n- maximum length: 32 characters\n\nExample: archuser"
		if [[ -n $validation_error ]]; then
			dialog_body+="\n\nError: $validation_error"
		fi

		input_box "$title" "$dialog_body" "$initial_value" 14 76
		value="$DIALOG_RESULT"
		status=$DIALOG_STATUS

		case $status in
			1|255)
				return 1
				;;
			0)
				;;
			*)
				return 1
				;;
		esac

		if [[ -z $value ]]; then
			validation_error="Username cannot be empty."
			initial_value="$value"
			continue
		fi

		if [[ ! $value =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
			validation_error="Invalid username: '$value'"
			initial_value="$value"
			continue
		fi

		printf '%s\n' "$value"
		return 0
	done
}

password_mode_for_value() {
	case ${2:-true}:${1-} in
		false:)
			printf 'unset\n'
			;;
		true:)
			printf 'empty\n'
			;;
		*)
			printf 'set\n'
			;;
	esac
}

password_mode_label() {
	case ${1:-unset} in
		set)
			printf 'set\n'
			;;
		empty)
			printf 'empty (password cleared)\n'
			;;
		*)
			printf 'not configured\n'
			;;
	esac
}

prompt_password() {
	local title=${1:?title is required}
	local allow_empty=${2:-true}
	local first=""
	local second=""
	local status=0
	local validation_error=""
	local prompt_text=""

	while true; do
		prompt_text="Enter the password."
		if [[ $allow_empty == "true" ]]; then
			prompt_text+=" Leave blank to skip password setup."
		else
			prompt_text+=" A password is required for this setting."
		fi
		prompt_text+="\n\nConstraints:\n- entry is non-interactive\n- non-empty passwords require confirmation"
		if [[ $allow_empty == "true" ]]; then
			prompt_text+="\n- blank input clears the password"
		fi
		prompt_text+="\n- non-empty values must be 8 to 72 characters"
		prompt_text+="\n- ':' is not allowed"
		if [[ -n $validation_error ]]; then
			prompt_text+="\n\nError: $validation_error"
		fi

		password_box "$title" "$prompt_text" 15 76
		first="$DIALOG_RESULT"
		status=$DIALOG_STATUS
		case $status in
			0)
				;;
			1|255)
				return 1
				;;
			*)
				return 1
				;;
		esac

		if [[ -z $first ]]; then
			if [[ $allow_empty == "true" ]]; then
				printf ''
				return 0
			fi
			validation_error="A password is required."
			continue
		fi

		if [[ $first == *:* ]]; then
			validation_error="Passwords cannot contain ':'."
			continue
		fi

		if (( ${#first} < 8 )); then
			validation_error="Password must be at least 8 characters long."
			continue
		fi

		if (( ${#first} > 72 )); then
			validation_error="Password must be 72 characters or fewer."
			continue
		fi

		password_box "$title" "Re-enter the password to confirm." 12 76
		second="$DIALOG_RESULT"
		status=$DIALOG_STATUS
		case $status in
			0)
				;;
			1|255)
				return 1
				;;
			*)
				return 1
				;;
		esac

		if [[ $first != "$second" ]]; then
			validation_error="Passwords did not match. Please try again."
			continue
		fi

		printf '%s\n' "$first"
		return 0
	done
}

prompt_password_or_keep() {
	local title=${1:?title is required}
	local current_password=${2-}
	local current_mode=${3:-unset}
	local allow_empty=${4:-true}

	if [[ $current_mode != "unset" ]]; then
		if confirm "$title" "A password configuration is already loaded for this session.\n\nCurrent state: $(password_mode_label "$current_mode")\n\nKeep it?" 12 72; then
			printf '%s\n' "$current_password"
			return 0
		fi
	fi

	prompt_password "$title" "$allow_empty"
}