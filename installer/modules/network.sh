#!/usr/bin/env bash

initialize_pacman_environment() {
	run_step "Initializing pacman keyring" pacman-key --init
	run_step "Populating pacman keyring" pacman-key --populate archlinux
	run_pacman_step_with_retry "Refreshing archlinux-keyring" 3 -Sy archlinux-keyring
	run_optional_pacman_step_with_retry "Installing reflector on the live environment" 3 -Sy reflector
	run_optional_step_with_retry "Refreshing pacman mirrors" 3 reflector --latest 10 --protocol https --connection-timeout 5 --download-timeout 15 --sort rate --save /etc/pacman.d/mirrorlist
	run_pacman_step_with_retry "Refreshing pacman package databases" 3 -Syy
	return 0
}