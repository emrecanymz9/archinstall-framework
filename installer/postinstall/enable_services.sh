#!/usr/bin/env bash

postinstall_services_chroot_snippet() {
	cat <<'EOF'
enable_service_if_present() {
	local service_name=
	service_name=\${1:?service name is required}
	if systemctl list-unit-files "\$service_name" >/dev/null 2>&1; then
		systemctl enable "\$service_name" || true
	else
		echo "[WARN] Optional service not present: \$service_name"
	fi
}

run_postinstall_service_enablement() {
	log_chroot_step "Enabling post-install services"
	if [[ -x /usr/bin/NetworkManager || -f /usr/bin/NetworkManager ]]; then
		systemctl enable NetworkManager.service || true
	else
		echo "[WARN] NetworkManager binary not found in target; skipping enable"
	fi

	if command -v iwctl >/dev/null 2>&1; then
		install -d -m 755 /etc/NetworkManager/conf.d
		cat > /etc/NetworkManager/conf.d/wifi_backend.conf <<'NMCONFIGEOF'
[device]
wifi.backend=iwd
NMCONFIGEOF
		systemctl enable iwd.service || true
	fi

	case \$TARGET_DISPLAY_MANAGER in
		greetd)
			systemctl disable sddm.service 2>/dev/null || true
			enable_service_if_present greetd.service
			;;
		sddm)
			systemctl disable greetd.service 2>/dev/null || true
			enable_service_if_present sddm.service
			;;
		none)
			systemctl disable greetd.service 2>/dev/null || true
			systemctl disable sddm.service 2>/dev/null || true
			;;
		*)
			;;
	 esac

	if [[ \$TARGET_SNAPSHOT_PROVIDER == "snapper" ]]; then
		enable_service_if_present snapper-timeline.timer
		enable_service_if_present snapper-cleanup.timer
	fi
}
EOF
}
