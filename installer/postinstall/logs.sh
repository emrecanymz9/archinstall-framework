#!/usr/bin/env bash

postinstall_logs_chroot_snippet() {
	cat <<'EOF'
persist_install_logs() {
	local source_log=/root/archinstall.log
	local target_user_home="/home/$TARGET_USERNAME"

	if [[ ! -f $source_log ]]; then
		return 0
	fi

	install -d -m 0755 /var/log
	install -m 0644 "$source_log" /var/log/archinstall.log || true

	if [[ -d $target_user_home ]]; then
		install -m 0644 "$source_log" "$target_user_home/install.log" || true
		chown "$TARGET_USERNAME:$TARGET_USERNAME" "$target_user_home/install.log" 2>/dev/null || true
	fi
}

persist_install_logs
EOF
}

export_install_logs_to_target() {
	local install_log_path=${1:?install log path is required}
	local username=${2:?username is required}

	if [[ ! -f $install_log_path ]]; then
		return 0
	fi

	install -d -m 0755 /mnt/root || return 1
	install -m 0644 "$install_log_path" /mnt/root/archinstall.log || return 1
	if [[ -d "/mnt/home/$username" ]]; then
		install -m 0644 "$install_log_path" "/mnt/home/$username/install.log" || return 1
	fi
}