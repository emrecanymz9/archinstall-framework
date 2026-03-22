#!/usr/bin/env bash

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

display_mode_label() {
	case ${1:-auto} in
		auto)
			printf 'Auto (prefer Wayland, fallback X11)\n'
			;;
		wayland)
			printf 'Wayland\n'
			;;
		x11)
			printf 'X11\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

display_manager_label() {
	case ${1:-none} in
		none)
			printf 'None\n'
			;;
		sddm)
			printf 'SDDM\n'
			;;
		greetd)
			printf 'greetd + tuigreet\n'
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

select_display_manager() {
	local desktop_profile=${1:-none}
	local selected="none"

	if [[ $desktop_profile != "kde" ]]; then
		printf 'none\n'
		return 0
	fi

	menu "Display Manager" "Choose the display manager for KDE Plasma." 14 76 4 \
		"sddm" "Recommended for KDE Plasma" \
		"greetd" "greetd with tuigreet"
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

select_display_mode() {
	local desktop_profile=${1:-none}
	local current_mode=${2:-auto}
	local selected="auto"

	if [[ $desktop_profile != "kde" ]]; then
		printf 'auto\n'
		return 0
	fi

	menu "Display Mode" "Choose the preferred KDE session mode.\n\nCurrent: $(display_mode_label "$current_mode")" 15 78 4 \
		"auto" "Prefer Wayland, fall back to X11 for VMs or weak graphics" \
		"wayland" "Force startplasma-wayland" \
		"x11" "Force startplasma-x11"
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

desktop_profile_packages() {
	local desktop_profile=${1:-none}
	local display_manager=${2:-none}
	local display_mode=${3:-auto}
	local -n package_ref=${4:?package reference is required}

	package_ref=()

	case $desktop_profile in
		none)
			return 0
			;;
		kde)
			package_ref=(
				git
				dialog
				plasma-x11-session
				plasma-desktop
				plasma-workspace
				plasma-nm
				plasma-pa
				konsole
				dolphin
				kate
				ark
				gwenview
				spectacle
				kde-gtk-config
				packagekit-qt6
				xdg-desktop-portal-kde
				pipewire
				pipewire-alsa
				pipewire-pulse
				pipewire-jack
				wireplumber
				bluez
				bluez-utils
				xorg-server
			)
			case $display_mode in
				auto|wayland|x11)
					;;
				*)
					return 1
					;;
			esac
			case $display_manager in
				sddm)
					package_ref+=(sddm)
					;;
				greetd)
					package_ref+=(greetd greetd-tuigreet)
					;;
			esac
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
