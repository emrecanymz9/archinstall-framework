#!/usr/bin/env bash

network_required_packages() {
	local -n package_ref=${1:?package reference is required}
	package_ref=(networkmanager iwd)
}

initialize_pacman_environment() {
	local mirrorlist_backup=/etc/pacman.d/mirrorlist.archinstall.bak

	run_step "Initializing pacman keyring" pacman-key --init
	run_step "Populating pacman keyring" pacman-key --populate archlinux
	run_pacman_step_with_retry "Refreshing archlinux-keyring" 3 -Sy archlinux-keyring
	run_optional_pacman_step_with_retry "Installing reflector on the live environment" 3 -Sy reflector
	if [[ -f /etc/pacman.d/mirrorlist ]]; then
		cp /etc/pacman.d/mirrorlist "$mirrorlist_backup" 2>/dev/null || true
	fi
	if command -v reflector >/dev/null 2>&1; then
		if ! run_optional_step_with_retry "Refreshing pacman mirrors" 3 timeout 60 reflector --latest 10 --protocol https --connection-timeout 5 --download-timeout 15 --timeout 15 --sort rate --save /etc/pacman.d/mirrorlist; then
			if [[ -f $mirrorlist_backup ]]; then
				cp "$mirrorlist_backup" /etc/pacman.d/mirrorlist 2>/dev/null || true
			fi
			print_install_error "Reflector mirror refresh failed. Continuing with the existing mirrorlist backup."
			log_line "[WARN] Reflector mirror refresh failed; falling back to the existing mirrorlist"
		fi
	fi
	run_pacman_step_with_retry "Refreshing pacman package databases" 3 -Syy
	return 0
}

enable_network_services() {
	echo "[INFO] Network service enablement is handled by installer/postinstall/services.sh"
	return 0
}
