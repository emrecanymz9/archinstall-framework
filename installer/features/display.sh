#!/usr/bin/env bash

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

desktop_profile_packages() {
	local desktop_profile=${1:-none}
	local display_manager=${2:-none}
	local display_session=${3:-wayland}
	local -n package_ref=${4:?package reference is required}
	local greeter=${5:-none}

	package_ref=()
	case $desktop_profile in
		none)
			return 0
			;;
		kde)
			package_ref=(
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
			)
			case $display_session in
				wayland|x11)
					;;
				*)
					return 1
					;;
			esac
			case $display_manager in
				greetd)
					package_ref+=(greetd)
					case $greeter in
						qtgreet)
							package_ref+=(greetd-qtgreet)
							;;
						*)
							package_ref+=(greetd-tuigreet)
							;;
					esac
					;;
				sddm)
					package_ref+=(sddm sddm-kcm)
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

collect_display_preferences() {
	local desktop_profile=${1:-none}
	local -n session_ref=${2:?display session reference is required}
	local -n manager_ref=${3:?display manager reference is required}
	local -n greeter_ref=${4:?greeter reference is required}
	local current_session
	local current_greeter

	current_session="$(state_or_default "DISPLAY_SESSION" "wayland")"
	current_greeter="$(state_or_default "GREETER" "tuigreet")"

	if [[ $desktop_profile == "none" ]]; then
		session_ref="wayland"
		manager_ref="none"
		greeter_ref="none"
		return 0
	fi

	session_ref="$(select_display_mode "$desktop_profile" "$current_session")" || return 1
	manager_ref="$(select_display_manager "$desktop_profile")" || return 1
	if [[ $manager_ref == "greetd" ]]; then
		greeter_ref="$(select_greeter_frontend "$desktop_profile" "$current_greeter")" || return 1
	else
		greeter_ref="none"
	fi
}

apply_display_state() {
	local desktop_profile=${1:-none}
	local -n session_ref=${2:?display session reference is required}
	local -n manager_ref=${3:?display manager reference is required}
	local -n greeter_ref=${4:?greeter reference is required}
	local resolved_session=""

	if [[ $desktop_profile == "none" ]]; then
		session_ref="wayland"
		manager_ref="none"
		greeter_ref="none"
	else
		resolved_session="$(normalize_display_session "$session_ref")"
		if [[ $resolved_session != "$session_ref" && $session_ref != "wayland" && $session_ref != "x11" ]]; then
			return 1
		fi
		session_ref="$resolved_session"
		case $manager_ref in
			sddm|greetd)
				;;
			*)
				return 1
				;;
		esac
		if [[ $manager_ref == "greetd" ]]; then
			case $greeter_ref in
				tuigreet|qtgreet)
					;;
				*)
					return 1
					;;
			esac
		else
			greeter_ref="none"
		fi
	fi

	resolved_session="$(normalize_display_session "$session_ref")"
	set_state "DISPLAY_SESSION" "$resolved_session" || return 1
	set_state "DISPLAY_MANAGER" "$manager_ref" || return 1
	set_state "GREETER" "$greeter_ref" || return 1
	return 0
}