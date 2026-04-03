#!/usr/bin/env bash

ARCHINSTALL_BACKTITLE=${ARCHINSTALL_BACKTITLE:-"ArchInstall Framework"}
ARCHINSTALL_FOOTER_HINTS=${ARCHINSTALL_FOOTER_HINTS:-"Use arrow keys to navigate. ENTER=Select. ESC=Back."}
UI_MODE=${UI_MODE:-dialog}
DIALOG_STATUS=${DIALOG_STATUS:-0}
DIALOG_RESULT=${DIALOG_RESULT:-""}
ARCHINSTALL_UI_MAX_RETRY=${ARCHINSTALL_UI_MAX_RETRY:-3}
ARCHINSTALL_UI_RETRY_COUNT=${ARCHINSTALL_UI_RETRY_COUNT:-0}
ARCHINSTALL_LAST_UI_FAILURE=${ARCHINSTALL_LAST_UI_FAILURE:-false}
ARCHINSTALL_TTY_FALLBACK_NOTICE_SHOWN=${ARCHINSTALL_TTY_FALLBACK_NOTICE_SHOWN:-false}

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

ui_force_tty() {
	[[ ${UI_MODE:-dialog} == "tty" ]]
}

debug_ui_mode() {
	local message="[DEBUG] UI mode: ${UI_MODE:-dialog}"

	printf '%s\n' "$message" >&2
	if [[ -n ${ARCHINSTALL_LOG:-} ]]; then
		printf '%s\n' "$message" >> "$ARCHINSTALL_LOG" 2>/dev/null || true
	fi
}

set_ui_mode() {
	local new_mode=${1:-dialog}

	if [[ $new_mode != "dialog" && $new_mode != "tty" ]]; then
		new_mode=tty
	fi

	if [[ ${UI_MODE:-dialog} == "$new_mode" ]]; then
		return 0
	fi

	UI_MODE=$new_mode
	debug_ui_mode
}

log_ui_error() {
	local message=${1:-"[UI ERROR] dialog failed"}
	local timestamp=""

	timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf 'unknown-time')"
	printf '%s\n' "$message" >&2
	if [[ -n ${ARCHINSTALL_LOG:-} ]]; then
		printf '[%s] %s\n' "$timestamp" "$message" >> "$ARCHINSTALL_LOG" 2>/dev/null || true
	fi
}

mark_ui_failure() {
	ARCHINSTALL_LAST_UI_FAILURE=true
	ARCHINSTALL_UI_RETRY_COUNT=$((ARCHINSTALL_UI_RETRY_COUNT + 1))

	if (( ARCHINSTALL_UI_RETRY_COUNT >= ARCHINSTALL_UI_MAX_RETRY )); then
		set_ui_mode tty
	fi
}

reset_ui_failure() {
	ARCHINSTALL_LAST_UI_FAILURE=false
	ARCHINSTALL_UI_RETRY_COUNT=0
}

notify_tty_fallback() {
	if [[ ${ARCHINSTALL_TTY_FALLBACK_NOTICE_SHOWN:-false} == true ]]; then
		return 0
	fi

	ARCHINSTALL_TTY_FALLBACK_NOTICE_SHOWN=true
	printf '\n[UI] Falling back to the plain terminal interface.\n' >&2
	printf '[UI] Dialog failed repeatedly or is unavailable. Continue in text mode.\n\n' >&2
}

dialog_runtime_error() {
	local output=${1:-}

	case $output in
		*"Unknown option"*|*"Error opening terminal"*|*"Expected at least"*|*"Usage:"*|*"unknown option"*)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

safe_dialog() {
	local tmpfile=""

	ARCHINSTALL_LAST_UI_FAILURE=false
	DIALOG_STATUS=0
	DIALOG_RESULT=""

	if ui_force_tty; then
		ARCHINSTALL_LAST_UI_FAILURE=true
		DIALOG_STATUS=1
		return 1
	fi

	if ! require_dialog >/dev/null 2>&1; then
		log_ui_error "[UI ERROR] dialog is unavailable; switching to TTY fallback"
		mark_ui_failure
		set_ui_mode tty
		DIALOG_STATUS=127
		return 1
	fi

	tmpfile="$(mktemp 2>/dev/null)"
	if [[ -z $tmpfile ]]; then
		log_ui_error "[UI ERROR] mktemp failed for dialog capture; switching to TTY fallback"
		mark_ui_failure
		set_ui_mode tty
		DIALOG_STATUS=1
		return 1
	fi

	dialog "$@" 2> "$tmpfile"
	DIALOG_STATUS=$?
	DIALOG_RESULT="$(cat "$tmpfile" 2>/dev/null || true)"
	rm -f "$tmpfile"

	if [[ $DIALOG_STATUS -eq 0 ]]; then
		reset_ui_failure
		return 0
	fi

	if [[ $DIALOG_STATUS -ne 1 && $DIALOG_STATUS -ne 255 ]]; then
		log_ui_error "[UI ERROR] dialog failed (status: $DIALOG_STATUS): $DIALOG_RESULT"
		mark_ui_failure
		set_ui_mode tty
		return 1
	fi

	ARCHINSTALL_LAST_UI_FAILURE=false
	return 1
}

tty_prompt() {
	local prompt=${1:-"> "}
	local input=""

	printf '%s' "$prompt" >/dev/tty
	if ! IFS= read -r input </dev/tty; then
		return 1
	fi

	printf '%s' "$input"
}

tty_menu() {
	local title=${1:?menu title is required}
	local prompt=${2:?menu prompt is required}
	local response=""
	local total=0
	local index=1
	local option_tag=""
	local option_desc=""
	local -a options=()

	shift 5
	options=("$@")
	total=$((${#options[@]} / 2))
	DIALOG_RESULT=""

	printf '\n%s\n' "$(sanitize_dialog_text "$title")" >/dev/tty
	printf '%s\n\n' "$(sanitize_dialog_text "$prompt")" >/dev/tty

	while (( index <= total )); do
		option_tag=${options[$(((index - 1) * 2))]}
		option_desc=${options[$((((index - 1) * 2) + 1))]}
		printf '  %s) %s - %s\n' "$index" "$option_tag" "$option_desc" >/dev/tty
		index=$((index + 1))
	done

	printf '\nEnter a number or q to go back: ' >/dev/tty
	if ! IFS= read -r response </dev/tty; then
		return 1
	fi

	case $response in
		q|Q|quit|back|"")
			return 1
			;;
		*[!0-9]*)
			return 1
			;;
	esac

	if (( response < 1 || response > total )); then
		return 1
	fi

	DIALOG_RESULT="${options[$(((response - 1) * 2))]}"
	return 0
}

tty_msg() {
	local title=${1:-"Message"}
	local body=${2:-""}

	printf '\n%s\n' "$(sanitize_dialog_text "$title")" >/dev/tty
	printf '%s\n' "$(sanitize_dialog_text "$body")" >/dev/tty
	printf '\nPress ENTER to continue...' >/dev/tty
	IFS= read -r _ </dev/tty || return 1
	return 0
}

tty_confirm() {
	local title=${1:-"Confirm"}
	local body=${2:-"Proceed?"}
	local response=""

	printf '\n%s\n' "$(sanitize_dialog_text "$title")" >/dev/tty
	printf '%s\n' "$(sanitize_dialog_text "$body")" >/dev/tty
	printf 'Confirm [y/N]: ' >/dev/tty
	if ! IFS= read -r response </dev/tty; then
		return 1
	fi

	case $response in
		[Yy]|[Yy][Ee][Ss])
			return 0
			;;
		*)
			return 1
			;;
	esac
}

tty_input_box() {
	local title=${1:-"Input"}
	local body=${2:-"Enter a value:"}
	local initial_value=${3:-""}
	local response=""
	DIALOG_RESULT=""

	printf '\n%s\n' "$(sanitize_dialog_text "$title")" >/dev/tty
	printf '%s\n' "$(sanitize_dialog_text "$body")" >/dev/tty
	if [[ -n $initial_value ]]; then
		printf 'Current value [%s]: ' "$(sanitize_dialog_text "$initial_value")" >/dev/tty
	else
		printf 'Value: ' >/dev/tty
	fi
	if ! IFS= read -r response </dev/tty; then
		return 1
	fi

	DIALOG_RESULT="$(sanitize_dialog_text "$response")"
	return 0
}

tty_password_box() {
	local title=${1:-"Password"}
	local body=${2:-"Enter a password:"}
	local response=""
	DIALOG_RESULT=""

	printf '\n%s\n' "$(sanitize_dialog_text "$title")" >/dev/tty
	printf '%s\n' "$(sanitize_dialog_text "$body")" >/dev/tty
	printf 'Password: ' >/dev/tty
	if ! IFS= read -r -s response </dev/tty; then
		printf '\n' >/dev/tty
		return 1
	fi
	printf '\n' >/dev/tty

	DIALOG_RESULT="$(sanitize_dialog_text "$response")"
	return 0
}

menu() {
	local title=${1:?menu title is required}
	local prompt=${2:?menu prompt is required}
	local height=${3:-18}
	local width=${4:-70}
	local menu_height=${5:-8}
	local sanitized_title=""
	local sanitized_prompt=""
	local status

	shift 5
	sanitized_title="$(sanitize_dialog_text "$title")"
	sanitized_prompt="$(sanitize_dialog_text "$prompt")"
	DIALOG_RESULT=""

	if ui_force_tty; then
		notify_tty_fallback
		tty_menu "$title" "$prompt" "$height" "$width" "$menu_height" "$@"
		status=$?
	else
		safe_dialog \
			--clear \
			--backtitle "$ARCHINSTALL_BACKTITLE" \
			--title "$sanitized_title" \
			--cancel-label "Back" \
			--visit-items \
			--menu "$(sanitize_dialog_text "$(with_footer_hints "$sanitized_prompt")")" \
			"$height" "$width" "$menu_height" \
			"$@" \
			3>&1 1>&2 2>&3
		status=$DIALOG_STATUS
		if [[ $status -ne 0 && ${ARCHINSTALL_LAST_UI_FAILURE:-false} == true ]]; then
			notify_tty_fallback
			tty_menu "$title" "$prompt" "$height" "$width" "$menu_height" "$@"
			status=$?
		fi
	fi

	if [[ $status -eq 0 ]]; then
		DIALOG_RESULT="$(sanitize_dialog_choice "$DIALOG_RESULT")"
	fi

	DIALOG_STATUS=$status
	return "$status"
}

msg() {
	local title=${1:-"Message"}
	local body=${2:-""}
	local height=${3:-10}
	local width=${4:-70}

	if ui_force_tty; then
		notify_tty_fallback
		tty_msg "$title" "$body"
		return $?
	fi

	if ! safe_dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$(sanitize_dialog_text "$title")" --msgbox "$(sanitize_dialog_text "$body")" "$height" "$width"; then
		if [[ ${ARCHINSTALL_LAST_UI_FAILURE:-false} == true ]]; then
			notify_tty_fallback
			tty_msg "$title" "$body"
			return $?
		fi
		return 1
	fi
}

confirm() {
	local title=${1:-"Confirm"}
	local body=${2:-"Proceed?"}
	local height=${3:-10}
	local width=${4:-70}

	if ui_force_tty; then
		notify_tty_fallback
		tty_confirm "$title" "$(with_footer_hints "$body" "Type y to continue")"
		return $?
	fi

	if ! safe_dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$(sanitize_dialog_text "$title")" --defaultno --yesno "$(sanitize_dialog_text "$(with_footer_hints "$body" "ESC=Back, LEFT/RIGHT=Choose")")" "$height" "$width"; then
		if [[ ${ARCHINSTALL_LAST_UI_FAILURE:-false} == true ]]; then
			notify_tty_fallback
			tty_confirm "$title" "$(with_footer_hints "$body" "Type y to continue")"
			return $?
		fi
		return 1
	fi
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
	local status

	sanitized_title="$(sanitize_dialog_text "$title")"
	sanitized_body="$(sanitize_dialog_text "$body")"
	sanitized_initial_value="$(sanitize_dialog_text "$initial_value")"
	DIALOG_RESULT=""

	if ui_force_tty; then
		notify_tty_fallback
		tty_input_box "$title" "$body" "$initial_value" "$height" "$width"
		status=$?
	else
		safe_dialog \
			--clear \
			--backtitle "$ARCHINSTALL_BACKTITLE" \
			--title "$sanitized_title" \
			--inputbox "$sanitized_body" \
			"$height" "$width" "$sanitized_initial_value" \
			3>&1 1>&2 2>&3
		status=$DIALOG_STATUS
		if [[ $status -ne 0 && ${ARCHINSTALL_LAST_UI_FAILURE:-false} == true ]]; then
			notify_tty_fallback
			tty_input_box "$title" "$body" "$initial_value" "$height" "$width"
			status=$?
		fi
	fi

	if [[ $status -eq 0 ]]; then
		DIALOG_RESULT="$(sanitize_dialog_text "$DIALOG_RESULT")"
	fi

	DIALOG_STATUS=$status
	return "$status"
}

password_box() {
	local title=${1:-"Password"}
	local body=${2:-"Enter a password:"}
	local height=${3:-10}
	local width=${4:-70}
	local sanitized_title=""
	local sanitized_body=""
	local status

	sanitized_title="$(sanitize_dialog_text "$title")"
	sanitized_body="$(sanitize_dialog_text "$body")"
	DIALOG_RESULT=""

	if ui_force_tty; then
		notify_tty_fallback
		tty_password_box "$title" "$body" "$height" "$width"
		status=$?
	else
		safe_dialog \
			--clear \
			--backtitle "$ARCHINSTALL_BACKTITLE" \
			--title "$sanitized_title" \
			--insecure \
			--passwordbox "$sanitized_body" \
			"$height" "$width" \
			3>&1 1>&2 2>&3
		status=$DIALOG_STATUS
		if [[ $status -ne 0 && ${ARCHINSTALL_LAST_UI_FAILURE:-false} == true ]]; then
			notify_tty_fallback
			tty_password_box "$title" "$body" "$height" "$width"
			status=$?
		fi
	fi

	if [[ $status -eq 0 ]]; then
		DIALOG_RESULT="$(sanitize_dialog_text "$DIALOG_RESULT")"
	fi

	DIALOG_STATUS=$status
	return "$status"
}

progress() {
	local title=${1:-"Working"}
	local body=${2:-"Please wait..."}
	local height=${3:-8}
	local width=${4:-70}

	if ui_force_tty; then
		notify_tty_fallback
		printf '\n%s\n%s\n' "$(sanitize_dialog_text "$title")" "$(sanitize_dialog_text "$body")" >/dev/tty
		return 0
	fi

	if ! safe_dialog --clear --backtitle "$ARCHINSTALL_BACKTITLE" --title "$(sanitize_dialog_text "$title")" --infobox "$(sanitize_dialog_text "$body")" "$height" "$width"; then
		if [[ ${ARCHINSTALL_LAST_UI_FAILURE:-false} == true ]]; then
			notify_tty_fallback
			printf '\n%s\n%s\n' "$(sanitize_dialog_text "$title")" "$(sanitize_dialog_text "$body")" >/dev/tty
			return 0
		fi
		return 1
	fi
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

tty_checklist() {
	local title=${1:?checklist title is required}
	local prompt=${2:?checklist prompt is required}
	local total=0
	local index=1
	local option_tag=""
	local option_desc=""
	local option_status=""
	local response=""
	local -a options=()
	local -a selected_indices=()

	shift 5
	options=("$@")
	total=$((${#options[@]} / 3))
	DIALOG_RESULT=""

	printf '\n%s\n' "$(sanitize_dialog_text "$title")" >/dev/tty
	printf '%s\n\n' "$(sanitize_dialog_text "$prompt")" >/dev/tty

	while (( index <= total )); do
		option_tag=${options[$(( (index - 1) * 3 ))]}
		option_desc=${options[$(( (index - 1) * 3 + 1 ))]}
		option_status=${options[$(( (index - 1) * 3 + 2 ))]}
		local marker=" "
		[[ $option_status == "on" ]] && marker="*"
		[[ $option_status == "on" ]] && selected_indices+=("$index")
		printf '  [%s] %d) %s - %s\n' "$marker" "$index" "$option_tag" "$option_desc" >/dev/tty
		index=$(( index + 1 ))
	done

	printf '\nEnter numbers to toggle (space-separated) or press ENTER to accept: ' >/dev/tty
	if ! IFS= read -r response </dev/tty; then
		return 1
	fi

	case $response in
		q|Q|quit|back)
			return 1
			;;
	esac

	if [[ -n $response ]]; then
		local -a toggles
		read -ra toggles <<< "$response"
		for t in "${toggles[@]}"; do
			[[ $t =~ ^[0-9]+$ ]] || continue
			(( t >= 1 && t <= total )) || continue
			local found=false
			local -a new_sel=()
			for s in "${selected_indices[@]}"; do
				if [[ $s == "$t" ]]; then
					found=true
				else
					new_sel+=("$s")
				fi
			done
			[[ $found == true ]] || new_sel+=("$t")
			selected_indices=("${new_sel[@]}")
		done
	fi

	local -a result_tags=()
	for s in "${selected_indices[@]}"; do
		result_tags+=("${options[$(( (s - 1) * 3 ))]}")
	done

	DIALOG_RESULT="${result_tags[*]}"
	return 0
}

checklist_box() {
	local title=${1:?checklist title is required}
	local body=${2:?checklist prompt is required}
	local height=${3:-20}
	local width=${4:-76}
	local list_height=${5:-10}
	local status

	shift 5
	DIALOG_RESULT=""

	if ui_force_tty; then
		notify_tty_fallback
		tty_checklist "$title" "$body" "$height" "$width" "$list_height" "$@"
		status=$?
	else
		safe_dialog \
			--clear \
			--backtitle "$ARCHINSTALL_BACKTITLE" \
			--title "$(sanitize_dialog_text "$title")" \
			--checklist "$(sanitize_dialog_text "$(with_footer_hints "$body" "SPACE=Toggle, ENTER=Confirm, ESC=Back")")" \
			"$height" "$width" "$list_height" \
			"$@" \
			3>&1 1>&2 2>&3
		status=$DIALOG_STATUS
		if [[ $status -ne 0 && ${ARCHINSTALL_LAST_UI_FAILURE:-false} == true ]]; then
			notify_tty_fallback
			tty_checklist "$title" "$body" "$height" "$width" "$list_height" "$@"
			status=$?
		fi
	fi

	if [[ $status -eq 0 ]]; then
		DIALOG_RESULT="${DIALOG_RESULT//\"/}"
		DIALOG_RESULT="$(sanitize_dialog_text "$DIALOG_RESULT")"
	fi

	DIALOG_STATUS=$status
	return "$status"
}