#!/usr/bin/env bash

initialize_pacman_environment() {
	run_step "Refreshing archlinux-keyring" pacman -Sy --noconfirm archlinux-keyring || return 1
	run_step "Installing reflector on the live environment" pacman -S --needed --noconfirm reflector || return 1
	run_step "Refreshing pacman mirrors" reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist || return 1
	run_step "Refreshing pacman package databases" pacman -Syy --noconfirm || return 1
}