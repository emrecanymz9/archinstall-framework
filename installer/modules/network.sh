#!/usr/bin/env bash

initialize_pacman_environment() {
	run_optional_step "Refreshing archlinux-keyring" pacman -Sy --noconfirm archlinux-keyring
	run_optional_step "Installing reflector on the live environment" pacman -S --needed --noconfirm reflector
	run_optional_step "Refreshing pacman mirrors" reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
	run_optional_step "Refreshing pacman package databases" pacman -Syy --noconfirm
	return 0
}