#!/usr/bin/env bash

ARCHINSTALL_BACKTITLE=${ARCHINSTALL_BACKTITLE:-"ArchInstall Framework"}
ARCHINSTALL_FOOTER_HINTS=${ARCHINSTALL_FOOTER_HINTS:-"Use arrow keys to navigate. ENTER=Select. ESC=Back."}

sanitize_dialog_text() {
	printf '%s' "${1-}" | LC_ALL=C tr -cd '\11\12\15\40-\176'
}

sanitize_dialog_choice() {
	printf '%s' "${1-}" | LC_ALL=C tr -cd '[:alnum:]_.:/-'
}

with_footer_hints() {
	local body=${1-}
	local hints=${2:-$ARCHINSTALL_FOOTER_HINTS}

	if [[ -z $hints ]]; then
		printf '%s' "$body"
		return 0
	fi

	printf '%s\n\n%s' "$body" "$hints"
}

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
	local sanitized_title=""
	local sanitized_prompt=""
	local selection
	local status

	shift 5
	require_dialog || return $?
	sanitized_title="$(sanitize_dialog_text "$title")"
	sanitized_prompt="$(sanitize_dialog_text "$prompt")"

	selection="$(dialog \
		--clear \
		--backtitle "$ARCHINSTALL_BACKTITLE" \
		--title "$sanitized_title" \
		--cancel-label "Back" \
		--visit-items \
		--menu "$(sanitize_dialog_text "$(with_footer_hints "$sanitized_prompt")")" \
		"$height" "$width" "$menu_height" \
		"$@" \
		3>&1 1>&2 2>&3)"
	status=$?

	if [[ $status -eq 0 ]]; then
		printf '%s\n' "$(sanitize_dialog_choice "$selection")"
	fi

	return "$status"
}

msg() {
	local title=${1:-"Message"}
	local body=${2:-""}
	local height=${3:-10}
	local width=${4:-70}

	require_dialog || return $?
	dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$(sanitize_dialog_text "$title")" --msgbox "$(sanitize_dialog_text "$body")" "$height" "$width"
}

confirm() {
	local title=${1:-"Confirm"}
	local body=${2:-"Proceed?"}
	local height=${3:-10}
	local width=${4:-70}

	require_dialog || return $?
	dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$(sanitize_dialog_text "$title")" --defaultno --yesno "$(sanitize_dialog_text "$(with_footer_hints "$body" "ESC=Back, LEFT/RIGHT=Choose")")" "$height" "$width"
}

input_box() {
	local title=${1:-"Input"}
	local body=${2:-"Enter a value:"}
	local initial_value=${3:-""}
	local height=${4:-10}
	local width=${5:-70}
	local sanitized_title=""
	local sanitized_body=""
	local sanitized_initial_value=""
	local input_value
	local status

	require_dialog || return $?
	sanitized_title="$(sanitize_dialog_text "$title")"
	sanitized_body="$(sanitize_dialog_text "$body")"
	sanitized_initial_value="$(sanitize_dialog_text "$initial_value")"

	input_value="$(dialog \
		--clear \
		--backtitle "$ARCHINSTALL_BACKTITLE" \
		--title "$sanitized_title" \
		--inputbox "$sanitized_body" \
		"$height" "$width" "$sanitized_initial_value" \
		3>&1 1>&2 2>&3)"
	status=$?

	if [[ $status -eq 0 ]]; then
		printf '%s\n' "$(sanitize_dialog_text "$input_value")"
	fi

	return "$status"
}

password_box() {
	local title=${1:-"Password"}
	local body=${2:-"Enter a password:"}
	local height=${3:-10}
	local width=${4:-70}
	local sanitized_title=""
	local sanitized_body=""
	local input_value
	local status

	require_dialog || return $?
	sanitized_title="$(sanitize_dialog_text "$title")"
	sanitized_body="$(sanitize_dialog_text "$body")"

	input_value="$(dialog \
		--clear \
		--backtitle "$ARCHINSTALL_BACKTITLE" \
		--title "$sanitized_title" \
		--insecure \
		--passwordbox "$sanitized_body" \
		"$height" "$width" \
		3>&1 1>&2 2>&3)"
	status=$?

	if [[ $status -eq 0 ]]; then
		printf '%s\n' "$(sanitize_dialog_text "$input_value")"
	fi

	return "$status"
}

progress() {
	local title=${1:-"Working"}
	local body=${2:-"Please wait..."}
	local height=${3:-8}
	local width=${4:-70}

	require_dialog || return $?
	dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$(sanitize_dialog_text "$title")" --infobox "$(sanitize_dialog_text "$body")" "$height" "$width"
}

info_box() {
	local title=${1:-"Information"}
	local body=${2:-""}
	local height=${3:-12}
	local width=${4:-76}

	msg "$title" "$(with_footer_hints "$body")" "$height" "$width"
}

warning_box() {
	local title=${1:-"Warning"}
	local body=${2:-"Review this action carefully."}
	local height=${3:-12}
	local width=${4:-76}

	msg "$title" "$(with_footer_hints "$body" "This action may be destructive. ESC=Back, ENTER=Continue")" "$height" "$width"
}

step_box() {
	local title=${1:-"Working"}
	local body=${2:-"Preparing next step..."}
	local height=${3:-10}
	local width=${4:-76}

	progress "$title" "$(sanitize_dialog_text "$body")" "$height" "$width"
}

error_box() {
	local title=${1:-"Error"}
	local body=${2:-"An unexpected error occurred."}
	msg "$title" "$body" 12 76
}

clear_screen() {
	clear
}