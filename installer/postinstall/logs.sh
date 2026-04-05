#!/usr/bin/env bash

export_install_logs_to_target() {
	local install_log_path=${1:?install log path is required}
	local username=${2:?username is required}

	if [[ ! -f $install_log_path ]]; then
		return 0
	fi

	install -d -m 0755 /mnt/var/log || return 1
	install -m 0644 "$install_log_path" /mnt/var/log/archinstall.log || return 1
	if [[ -d "/mnt/home/$username" ]]; then
		install -m 0644 "$install_log_path" "/mnt/home/$username/install.log" || return 1
	fi
}