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
			printf 'startplasma-x11\n'
			;;
		*)
			printf 'startplasma-wayland\n'
			;;
	esac
}

build_greetd_command() {
	local greeter=${1:-tuigreet}
	local session_command=${2:-startplasma-wayland}

	case $greeter in
		qtgreet)
			printf 'qtgreet\n'
			;;
		*)
			printf 'tuigreet --time --cmd %s\n' "$session_command"
			;;
	esac
}

install_greetd() {
	local greeter=${1:-tuigreet}
	local session_command=${2:-startplasma-wayland}

	log_chroot_step "Configuring greetd"
	if [[ $greeter == "qtgreet" ]]; then
		install_packages_if_missing greetd greetd-qtgreet || true
	else
		greeter="tuigreet"
		install_packages_if_missing greetd greetd-tuigreet || true
	fi
	install -d -m 0755 /etc/greetd
	cat > /etc/greetd/config.toml <<EOT
[terminal]
vt = 1

[default_session]
command = "$(build_greetd_command "$greeter" "$session_command")"
user = "greeter"
EOT
	rm -f /etc/sddm.conf.d/session.conf 2>/dev/null || true
	write_display_manager_fallback_notice "$session_command"
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
			install_greetd "$TARGET_GREETER" "$session_command"
			;;
		sddm)
			install_sddm "$TARGET_RESOLVED_DISPLAY_SESSION" "$session_command"
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
