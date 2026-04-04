#!/usr/bin/env bash

DESKTOP_MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -r "$DESKTOP_MODULE_DIR/../features/display.sh" ]]; then
	# shellcheck source=installer/features/display.sh
	source "$DESKTOP_MODULE_DIR/../features/display.sh"
fi

desktop_profile_label() {
	case ${1:-none} in
		none)
			printf 'None\n'
			;;
		kde)
			printf 'KDE Plasma\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

select_desktop_profile() {
	local selected=""

	menu "Desktop Profile" "Choose an optional desktop profile." 14 76 4 \
		"none" "No desktop environment" \
		"kde" "KDE Plasma with Wayland and X11 session support"
	selected="$DIALOG_RESULT"
	case $DIALOG_STATUS in
		0)
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
desktop_profile_requires() {
	local desktop_profile=${1:-none}
	local -n package_ref=${2:?package reference is required}

	package_ref=()
	case $desktop_profile in
		none)
			return 0
			;;
		kde)
			package_ref=(systemctl)
			;;
		*)
			return 1
			;;
	esac
}
