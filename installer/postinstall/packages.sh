#!/usr/bin/env bash

postinstall_packages_chroot_snippet() {
	cat <<'EOF'
map_selected_package_token() {
	case ${1:-} in
		editor-nano|nano)
			printf 'nano\n'
			;;
		editor-micro|micro)
			printf 'micro\n'
			;;
		editor-vim|vim)
			printf 'vim\n'
			;;
		editor-kate|kate)
			printf 'kate\n'
			;;
		firefox|keepassxc|fastfetch|code)
			printf '%s\n' "$1"
			;;
		vscode)
			printf 'code\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

append_selected_package() {
	local package_name=${1:-}
	local existing=""

	[[ -n $package_name ]] || return 0
	for existing in "${SELECTED_PACKAGES[@]}"; do
		if [[ $existing == "$package_name" ]]; then
			return 0
		fi
	done
	SELECTED_PACKAGES+=("$package_name")
}

ensure_session_launcher() {
	install -d -m 0755 /usr/local/bin
	cat > /usr/local/bin/archinstall-start-session <<'EOT'
#!/bin/bash
if [[ ${1:-wayland} == "x11" ]]; then
	export XDG_SESSION_TYPE=x11
	exec startplasma-x11
fi
export XDG_SESSION_TYPE=wayland
exec startplasma-wayland
EOT
	chmod +x /usr/local/bin/archinstall-start-session
}

build_selected_packages() {
	local token=""
	local mapped_package=""

	SELECTED_PACKAGES=()
	read -r -a _selected_tokens <<< "${TARGET_CUSTOM_TOOLS:-}"
	for token in "${_selected_tokens[@]}"; do
		[[ -n $token ]] || continue
		mapped_package="$(map_selected_package_token "$token")"
		append_selected_package "$mapped_package"
	done

	if [[ -n ${TARGET_EDITOR_CHOICE:-} ]]; then
		append_selected_package "$(map_selected_package_token "editor-${TARGET_EDITOR_CHOICE}")"
	fi
	if [[ ${TARGET_INCLUDE_VSCODE:-false} == "true" ]]; then
		append_selected_package code
	fi
	if [[ ${TARGET_DESKTOP_PROFILE:-none} == "kde" ]]; then
		append_selected_package plasma-meta
		append_selected_package kde-applications-meta
		append_selected_package konsole
		append_selected_package dolphin
		append_selected_package ksystemlog
	fi
}

install_selected_packages() {
	local -a pacman_opts=()
	local opt=""

	if ! command -v pacman >/dev/null 2>&1; then
		echo "[FAIL] pacman is missing inside the target chroot"
		exit 1
	fi

	build_selected_packages
	if (( ${#SELECTED_PACKAGES[@]} == 0 )); then
		echo "[WARN] Packages: no selected packages requested"
		return 0
	fi

	echo "[DEBUG] Packages: ${SELECTED_PACKAGES[*]}"
	while IFS= read -r -d '' opt; do
		pacman_opts+=("$opt")
	done < <(build_pacman_opts_array)

	if ! pacman -S "${pacman_opts[@]}" "${SELECTED_PACKAGES[@]}"; then
		echo "[FAIL] pacman failed while installing selected packages"
		exit 1
	fi
}

validate_installed_session_stack() {
	if ! command -v pacman >/dev/null 2>&1; then
		echo "[FAIL] pacman is missing inside the target chroot"
		exit 1
	fi
	if [[ ${TARGET_DESKTOP_PROFILE:-none} == "kde" ]]; then
		if ! command -v startplasma-wayland >/dev/null 2>&1; then
			echo "[FAIL] startplasma-wayland is missing after package installation"
			exit 1
		fi
		if ! command -v kded5 >/dev/null 2>&1 && ! command -v kded6 >/dev/null 2>&1; then
			echo "[FAIL] kded binary is missing after KDE package installation"
			exit 1
		fi
		if ! command -v konsole >/dev/null 2>&1; then
			echo "[WARN] konsole is missing after KDE package installation"
		fi
	fi
	if [[ ! -f /usr/local/bin/archinstall-start-session ]]; then
		echo "[FAIL] /usr/local/bin/archinstall-start-session is missing"
		exit 1
	fi
}

log_chroot_step "Installing selected packages"
install_selected_packages
log_chroot_step "Creating session launcher"
ensure_session_launcher
log_chroot_step "Validating installed packages and session stack"
validate_installed_session_stack
EOF
}