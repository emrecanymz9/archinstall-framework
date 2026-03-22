#!/usr/bin/env bash

desktop_profile_label() {
	case ${1:-none} in
		none)
			printf 'None\n'
			;;
		kde)
			printf 'KDE Plasma (Wayland)\n'
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
			printf 'greetd + qtgreet\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

select_desktop_profile() {
	local selected=""

	selected="$(menu "Desktop Profile" "Choose an optional desktop profile." 14 76 4 \
		"none" "No desktop environment" \
		"kde" "KDE Plasma (Wayland) with desktop packages")"
	case $? in
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

	selected="$(menu "Display Manager" "Choose the display manager for KDE Plasma." 14 76 4 \
		"sddm" "Recommended for KDE Plasma" \
		"greetd" "greetd with qtgreet")"
	case $? in
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
	local -n package_ref=${3:?package reference is required}

	package_ref=()

	case $desktop_profile in
		none)
			return 0
			;;
		kde)
			package_ref=(
				plasma
				kde-applications
				xdg-desktop-portal-kde
				pipewire
				pipewire-alsa
				pipewire-pulse
				pipewire-jack
				wireplumber
				bluez
				bluez-utils
			)
			case $display_manager in
				sddm)
					package_ref+=(sddm)
					;;
				greetd)
					package_ref+=(greetd qtgreet)
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
