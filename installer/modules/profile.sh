#!/usr/bin/env bash

select_common_value() {
	local title=${1:?title is required}
	local prompt=${2:?prompt is required}
	local current_value=${3-}
	local custom_prompt=${4:?custom prompt is required}
	local selected=""
	local custom_value=""
	local status=0

	shift 4

	selected="$(menu "$title" "$prompt\n\nCurrent: ${current_value:-Not set}" 18 76 8 "$@" \
		"custom" "Enter a custom value")"
	status=$?

	case $status in
		0)
			if [[ $selected == "custom" ]]; then
				custom_value="$(input_box "$title" "$custom_prompt" "$current_value" 12 76)"
				status=$?
				if [[ $status -ne 0 || -z $custom_value ]]; then
					return 1
				fi
				printf '%s\n' "$custom_value"
				return 0
			fi

			printf '%s\n' "$selected"
			return 0
			;;
		1|255)
			return 1
			;;
		*)
			return 1
			;;
	esac
}

select_timezone_value() {
	local current_value=${1:-Europe/Istanbul}

	select_common_value \
		"Timezone" \
		"Choose a timezone." \
		"$current_value" \
		"Enter a timezone such as Europe/Istanbul, UTC, or Europe/Berlin." \
		"Europe/Istanbul" "Turkey default" \
		"UTC" "Coordinated Universal Time" \
		"Europe/Berlin" "Central European Time" \
		"Europe/London" "United Kingdom" \
		"America/New_York" "US Eastern Time" \
		"Asia/Dubai" "Gulf Standard Time"
}

select_locale_value() {
	local current_value=${1:-en_US.UTF-8}

	select_common_value \
		"Locale" \
		"Choose a system locale." \
		"$current_value" \
		"Enter a locale such as en_US.UTF-8 or tr_TR.UTF-8." \
		"en_US.UTF-8" "US English" \
		"tr_TR.UTF-8" "Turkish" \
		"en_GB.UTF-8" "British English" \
		"de_DE.UTF-8" "German" \
		"fr_FR.UTF-8" "French"
}

select_keyboard_layout_value() {
	local current_value=${1:-us}

	select_common_value \
		"Keyboard Layout" \
		"Choose a console keymap." \
		"$current_value" \
		"Enter a keymap such as us, trq, trf, or de-latin1." \
		"us" "US English" \
		"trq" "Turkish Q" \
		"trf" "Turkish F" \
		"uk" "United Kingdom" \
		"de-latin1" "German" \
		"fr-latin9" "French"
}