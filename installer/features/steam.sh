#!/usr/bin/env bash

steam_required_packages() {
	local install_steam=${1:-false}
	local -n package_ref=${2:?package reference is required}

	package_ref=()
	if [[ $install_steam == "true" ]]; then
		package_ref+=(steam)
	fi
}

steam_prepare_live_environment() {
	local install_steam=${1:-false}

	if [[ $install_steam != "true" ]]; then
		return 0
	fi

	if declare -F enable_multilib_repo >/dev/null 2>&1; then
		enable_multilib_repo /etc/pacman.conf
	fi
}

steam_chroot_setup_snippet() {
	local install_steam=${1:-false}

	if [[ $install_steam != "true" ]]; then
		return 0
	fi

	cat <<'EOF'
log_chroot_step "Persisting multilib for Steam support"
if grep -q '^#\[multilib\]' /etc/pacman.conf; then
	sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
fi
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
	cat >> /etc/pacman.conf <<'PACMANMULTILIB'

[multilib]
Include = /etc/pacman.d/mirrorlist
PACMANMULTILIB
fi
EOF
}
