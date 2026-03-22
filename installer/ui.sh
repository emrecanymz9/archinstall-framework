#!/usr/bin/env bash

ARCHINSTALL_BACKTITLE=${ARCHINSTALL_BACKTITLE:-"ArchInstall Framework"}

require_dialog() {
	if command -v dialog >/dev/null 2>&1; then
		return 0
	fi

	printf 'dialog is required but was not found in PATH\n' >&2
	return 127
}

menu() {
	local title=${1:?menu title is required}
	local prompt=${2:?menu prompt is required}
	local height=${3:-18}
	local width=${4:-70}
	local menu_height=${5:-8}
	local selection
	local status

	shift 5
	require_dialog || return $?

	selection="$(dialog \
		--clear \
		--backtitle "$ARCHINSTALL_BACKTITLE" \
		--title "$title" \
		--menu "$prompt" \
		"$height" "$width" "$menu_height" \
		"$@" \
		3>&1 1>&2 2>&3)"
	status=$?

	if [[ $status -eq 0 ]]; then
		printf '%s\n' "$selection"
	fi

	return "$status"
}

msg() {
	local title=${1:-"Message"}
	local body=${2:-""}
	local height=${3:-10}
	local width=${4:-70}

	require_dialog || return $?
	dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$title" --msgbox "$body" "$height" "$width"
}

confirm() {
	local title=${1:-"Confirm"}
	local body=${2:-"Proceed?"}
	local height=${3:-10}
	local width=${4:-70}

	require_dialog || return $?
	dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$title" --yesno "$body" "$height" "$width"
}

progress() {
	local title=${1:-"Working"}
	local body=${2:-"Please wait..."}
	local height=${3:-8}
	local width=${4:-70}

	require_dialog || return $?
	dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$title" --infobox "$body" "$height" "$width"
}

error_box() {
	local title=${1:-"Error"}
	local body=${2:-"An unexpected error occurred."}
	msg "$title" "$body" 12 76
}

clear_screen() {
	clear
}