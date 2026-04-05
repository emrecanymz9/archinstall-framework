#!/usr/bin/env bash

display_manager_chroot_snippet() {
	local desktop_profile=${1:-none}

	if [[ $desktop_profile != "kde" ]]; then
		return 0
	fi

	cat <<'EOF'
write_display_manager_fallback_notice() {
	local fallback_command=${1:-startplasma-wayland}
	install -d -m 0755 /etc/profile.d
	cat > /etc/profile.d/archinstall-desktop-fallback.sh <<EOT
if [[ -z "\${DISPLAY:-}" && -z "\${WAYLAND_DISPLAY:-}" && "\$(tty 2>/dev/null || true)" == /dev/tty* ]]; then
	echo "Display manager failed, start KDE manually with: $fallback_command"
fi
EOT
}

write_x11_fallback_helper() {
	install -d -m 0755 /usr/local/bin
	cat > /usr/local/bin/archinstall-startplasma-x11 <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
printf 'exec startplasma-x11\n' > "$HOME/.xinitrc"
exec startx
EOT
	chmod 0755 /usr/local/bin/archinstall-startplasma-x11
}

plasma_session_command() {
	case ${1:-wayland} in
		x11)
			printf '/usr/local/bin/archinstall-start-session x11\n'
			;;
		*)
			printf '/usr/local/bin/archinstall-start-session wayland\n'
			;;
	esac
}

build_greetd_command() {
	local greeter=${1:-tuigreet}
	local session_command=${2:-startplasma-wayland}

	case $greeter in
		qtgreet)
			printf 'qtgreet --cmd %s\n' "$session_command"
			;;
		*)
			printf '/usr/bin/tuigreet --time --cmd %s\n' "$session_command"
			;;
	esac
}

ensure_greeter_user() {
	if id -u greeter >/dev/null 2>&1; then
		return 0
	fi

	echo "[DEBUG] Creating greeter user"
	if ! useradd -r -M -s /usr/bin/nologin -U greeter; then
		echo "[FAIL] Failed to create greeter user"
		return 1
	fi
	return 0
}

write_session_launcher() {
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
	chmod 0755 /usr/local/bin/archinstall-start-session
}

write_greetd_failure_logger() {
	install -d -m 0755 /etc/systemd/system
	cat > /etc/systemd/system/archinstall-greetd-failure.service <<'EOT'
[Unit]
Description=ArchInstall greetd failure logger

[Service]
Type=oneshot
ExecStart=/bin/bash -lc 'printf "[%s] greetd failed to start\n" "$(date "+%F %T")" >> /var/log/greetd-boot.log; systemctl status greetd --no-pager >> /var/log/greetd-boot.log 2>&1; journalctl -u greetd -b --no-pager >> /var/log/greetd-boot.log 2>&1 || true'
EOT

	install -d -m 0755 /etc/systemd/system/greetd.service.d
	cat > /etc/systemd/system/greetd.service.d/archinstall.conf <<'EOT'
[Unit]
OnFailure=archinstall-greetd-failure.service

[Service]
ExecStartPre=/bin/bash -lc 'test -f /etc/greetd/config.toml'
EOT
}

validate_greetd_setup() {
	local greeter=${1:-tuigreet}

	if [[ ! -f /etc/greetd/config.toml ]]; then
		echo "[FAIL] /etc/greetd/config.toml is missing"
		return 1
	fi
	case $greeter in
		qtgreet)
			if [[ ! -x /usr/bin/qtgreet ]]; then
				echo "[FAIL] /usr/bin/qtgreet is missing"
				return 1
			fi
			if ! grep -q '^command = "qtgreet --cmd ' /etc/greetd/config.toml; then
				echo "[FAIL] greetd config does not contain a valid qtgreet command"
				return 1
			fi
			;;
		*)
			if [[ ! -x /usr/bin/tuigreet ]]; then
				echo "[FAIL] /usr/bin/tuigreet is missing"
				return 1
			fi
			;;
	esac
	if [[ ! -x /usr/local/bin/archinstall-start-session ]]; then
		echo "[FAIL] /usr/local/bin/archinstall-start-session is missing"
		return 1
	fi
	return 0
}

install_greetd() {
	local greeter=${1:-tuigreet}
	local session_command=${2:-startplasma-wayland}

	log_chroot_step "Configuring greetd"
	if [[ $greeter == "qtgreet" ]]; then
		if ! install_packages_if_missing greetd greetd-qtgreet qt6-base; then
			echo "[FAIL] Could not install greetd qtgreet packages"
			return 1
		fi
	else
		greeter="tuigreet"
		if ! install_packages_if_missing greetd greetd-tuigreet; then
			echo "[FAIL] Could not install greetd tuigreet packages"
			return 1
		fi
	fi
	ensure_greeter_user || return 1
	install -d -m 0755 /etc/greetd
	write_session_launcher
	write_greetd_failure_logger
	cat > /etc/greetd/config.toml <<EOT
[terminal]
vt = 1

[default_session]
command = "$(build_greetd_command "$greeter" "$session_command")"
user = "greeter"
EOT
	if ! validate_greetd_setup "$greeter"; then
		echo "[FAIL] greetd validation failed after configuration"
		return 1
	fi
	echo "[DEBUG] greetd config written to /etc/greetd/config.toml"
	rm -f /etc/sddm.conf.d/session.conf 2>/dev/null || true
	write_display_manager_fallback_notice "$session_command"
	return 0
}

install_sddm() {
	local display_session=${1:-wayland}
	local session_command=${2:-startplasma-wayland}

	log_chroot_step "Configuring SDDM"
	install_packages_if_missing sddm sddm-kcm || true
	if ! command -v sddm >/dev/null 2>&1; then
		echo "[WARN] sddm binary not found in target system. Skipping SDDM configuration."
		write_display_manager_fallback_notice "$session_command"
		return 0
	fi
	install -d -m 0755 /etc/sddm.conf.d
	cat > /etc/sddm.conf.d/kde_settings.conf <<'SDDMCONF'
[Autologin]
Relogin=false
Session=
User=

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[Theme]
Current=breeze

[Users]
MaximumUid=60000
MinimumUid=1000
SDDMCONF
	cat > /etc/sddm.conf.d/session.conf <<EOT
[Autologin]
Session=$(if [[ "$display_session" == "x11" ]]; then printf 'plasma.desktop'; else printf 'plasmawayland.desktop'; fi)
EOT
	rm -f /etc/greetd/config.toml 2>/dev/null || true
	write_display_manager_fallback_notice "$session_command"
	return 0
}

apply_display_manager() {
	local session_command=""

	if [[ $TARGET_DESKTOP_PROFILE != "kde" ]]; then
		return 0
	fi

	log_chroot_step "Configuring KDE services"
	install_packages_if_missing plasma-desktop plasma-workspace || true
	install -d -m 0755 /etc/systemd/user/default.target.wants
	ln -sf /usr/lib/systemd/user/pipewire.service /etc/systemd/user/default.target.wants/pipewire.service
	ln -sf /usr/lib/systemd/user/pipewire-pulse.service /etc/systemd/user/default.target.wants/pipewire-pulse.service
	ln -sf /usr/lib/systemd/user/wireplumber.service /etc/systemd/user/default.target.wants/wireplumber.service

	log_chroot_step "Enforcing graphical target"
	systemctl set-default graphical.target || true

	write_x11_fallback_helper
	session_command="$(plasma_session_command "$TARGET_RESOLVED_DISPLAY_SESSION")"
	case $TARGET_DISPLAY_MANAGER in
		greetd)
			if [[ $TARGET_DESKTOP_PROFILE == "kde" ]]; then
				echo "[WARN] KDE selected with greetd; falling back to sddm for stability"
				install_sddm "$TARGET_RESOLVED_DISPLAY_SESSION" "$session_command" || echo "[WARN] SDDM fallback configuration failed"
			else
				install_greetd "$TARGET_GREETER" "$session_command" || echo "[WARN] greetd configuration failed; leaving manual session fallback in place"
			fi
			;;
		sddm)
			install_sddm "$TARGET_RESOLVED_DISPLAY_SESSION" "$session_command" || echo "[WARN] SDDM configuration failed; leaving manual session fallback in place"
			;;
		none)
			rm -f /etc/greetd/config.toml 2>/dev/null || true
			write_display_manager_fallback_notice "$session_command"
			;;
		*)
			echo "[WARN] Unknown display manager '$TARGET_DISPLAY_MANAGER'; leaving manual session fallback in place."
			write_display_manager_fallback_notice "$session_command"
			;;
	esac
}

apply_display_manager
EOF
}
