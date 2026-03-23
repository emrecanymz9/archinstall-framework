#!/usr/bin/env bash

install_profile_label() {
	case ${1:-daily} in
		daily)
			printf 'DAILY\n'
			;;
		dev)
			printf 'DEV\n'
			;;
		custom)
			printf 'CUSTOM\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

editor_choice_label() {
	case ${1:-nano} in
		nano)
			printf 'nano\n'
			;;
		micro)
			printf 'micro\n'
			;;
		vim)
			printf 'vim\n'
			;;
		kate)
			printf 'kate\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

select_install_profile() {
	local current_profile=${1:-daily}

	menu "Install Profile" "Choose the installer profile.\n\nCurrent: $(install_profile_label "$current_profile")" 16 76 4 \
		"daily" "Full KDE workstation with tools and minimal questions" \
		"dev" "Developer-oriented package set" \
		"custom" "Choose editors, tools, and optional components"

	case $DIALOG_STATUS in
		0)
			printf '%s\n' "$DIALOG_RESULT"
			return 0
			;;
		*)
			return 1
			;;
	esac
}

select_editor_choice() {
	local current_editor=${1:-nano}

	menu "Editors" "Choose the preferred editor package.\n\nCurrent: $(editor_choice_label "$current_editor")" 16 70 5 \
		"nano" "Small and familiar terminal editor" \
		"micro" "Friendly terminal editor with modern defaults" \
		"vim" "Modal editor for keyboard-driven workflows" \
		"kate" "KDE graphical editor"

	case $DIALOG_STATUS in
		0)
			printf '%s\n' "$DIALOG_RESULT"
			return 0
			;;
		*)
			return 1
			;;
	esac
}

profile_default_desktop_profile() {
	case ${1:-daily} in
		daily)
			printf 'kde\n'
			;;
		*)
			printf 'none\n'
			;;
	esac
}

profile_default_display_manager() {
	case ${1:-daily} in
		daily)
			printf 'sddm\n'
			;;
		*)
			printf 'none\n'
			;;
	esac
}

profile_default_display_mode() {
	case ${1:-daily} in
		daily)
			printf 'auto\n'
			;;
		*)
			printf 'auto\n'
			;;
	esac
}

csv_has_value() {
	local csv=${1:-}
	local needle=${2:-}
	local item=""

	IFS=',' read -r -a _csv_items <<< "$csv"
	for item in "${_csv_items[@]}"; do
		if [[ $item == "$needle" ]]; then
			return 0
		fi
	done

	return 1
}

install_profile_packages() {
	local install_profile=${1:-daily}
	local editor_choice=${2:-nano}
	local include_vscode=${3:-false}
	local custom_tools=${4:-}
	local -n package_ref=${5:?package reference is required}

	package_ref=()

	case $install_profile in
		daily)
			package_ref+=(nano curl wget htop tmux unzip p7zip rsync man-db man-pages less fastfetch)
			;;
		dev)
			package_ref+=(nano micro vim htop tmux ripgrep fd less man-db man-pages)
			if [[ $include_vscode == "true" ]]; then
				package_ref+=(code)
			fi
			;;
		custom)
			case $editor_choice in
				nano|micro|vim|kate)
					package_ref+=("$editor_choice")
					;;
			esac
			csv_has_value "$custom_tools" git && package_ref+=(git)
			csv_has_value "$custom_tools" base-devel && package_ref+=(base-devel)
			csv_has_value "$custom_tools" htop && package_ref+=(htop)
			csv_has_value "$custom_tools" tmux && package_ref+=(tmux)
			csv_has_value "$custom_tools" curl && package_ref+=(curl wget)
			csv_has_value "$custom_tools" fastfetch && package_ref+=(fastfetch)
			if [[ $include_vscode == "true" ]]; then
				package_ref+=(code)
			fi
			;;
		*)
			return 1
			;;
	esac
}