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
	case ${1:-wayland} in
		wayland)
			printf 'Wayland\n'
			;;
		x11)
			printf 'X11\n'
			;;
		*)
			printf 'Wayland\n'
			;;
	esac
}

display_manager_label() {
	case ${1:-none} in
		none)
			printf 'None\n'
			;;
		greetd)
			printf 'greetd\n'
			;;
		sddm)
			printf 'SDDM\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

greeter_frontend_label() {
	case ${1:-none} in
		none)
			printf 'None\n'
			;;
		tuigreet)
			printf 'tuigreet\n'
			;;
		qtgreet)
			printf 'qtgreet (requires plugin/AUR package source)\n'
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
	local selected="sddm"

	if [[ $desktop_profile != "kde" ]]; then
		printf 'none\n'
		return 0
	fi

	menu "Display Manager" "Choose the display manager for KDE Plasma." 16 76 4 \
		"sddm"   "SDDM - recommended default for KDE" \
		"greetd" "greetd - minimal display manager with selectable greeter"
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

select_greeter_frontend() {
	local desktop_profile=${1:-none}
	local current_frontend=${2:-tuigreet}

	if [[ $desktop_profile != "kde" ]]; then
		printf 'tuigreet\n'
		return 0
	fi

	menu "Greeter Frontend" "Choose the greetd frontend.\n\nCurrent: $(greeter_frontend_label "$current_frontend")\n\nqtgreet is optional and expects a plugin or custom package source to provide the binary." 16 78 4 \
		"tuigreet" "Default TUI greeter" \
		"qtgreet" "Optional Qt greeter for KDE deployments"

	case $DIALOG_STATUS in
		0)
			printf '%s\n' "$DIALOG_RESULT"
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
	local current_mode=${2:-wayland}
	local selected="wayland"

	if [[ $desktop_profile != "kde" ]]; then
		printf 'wayland\n'
		return 0
	fi

	menu "Display Mode" "Choose the KDE session mode.\n\nCurrent: $(display_mode_label "$current_mode")" 16 78 4 \
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
	local display_mode=${3:-wayland}
	local -n package_ref=${4:?package reference is required}
	local greeter_frontend=${5:-none}

	package_ref=()

	case $desktop_profile in
		none)
			return 0
			;;
		kde)
			package_ref=(
				git
				dialog
				xorg-xinit
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
				sddm
				sddm-kcm
			)
			case $display_mode in
				wayland|x11)
					;;
				*)
					return 1
					;;
			esac
			case $display_manager in
				greetd)
					package_ref+=(greetd)
					case $greeter_frontend in
						qtgreet)
							package_ref+=(greetd-qtgreet)
							;;
						none|tuigreet|*)
							package_ref+=(greetd-tuigreet)
							;;
					esac
					;;
				sddm)
					;;
				none)
					;;
				*)
					return 1
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
