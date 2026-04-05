#!/usr/bin/env bash

postinstall_services_chroot_snippet() {
	cat <<'EOF'
enable_service_if_present() {
	local service_name=
	service_name=${1:?service name is required}
	if systemctl list-unit-files "$service_name" >/dev/null 2>&1; then
		systemctl enable "$service_name" || true
	else
		echo "[WARN] Optional service not present: $service_name"
	fi
}

ensure_greetd_ready() {
	if [[ ! -f /etc/greetd/config.toml ]]; then
		echo "[FAIL] greetd selected but /etc/greetd/config.toml is missing"
		return 1
	fi
	if ! grep -q 'startplasma-wayland\|startplasma-x11\|archinstall-start-session' /etc/greetd/config.toml; then
		echo "[FAIL] greetd config does not contain a valid Plasma session command"
		return 1
	fi
	return 0
}

configure_vm_services() {
	case $TARGET_ENVIRONMENT_VENDOR in
		vmware)
			enable_service_if_present vmtoolsd.service
			;;
		virtualbox)
			enable_service_if_present vboxservice.service
			;;
		kvm|qemu)
			enable_service_if_present spice-vdagentd.service
			enable_service_if_present qemu-guest-agent.service
			;;
		hyperv)
			enable_service_if_present hv_fcopy_daemon.service
			enable_service_if_present hv_kvp_daemon.service
			enable_service_if_present hv_vss_daemon.service
			;;
		*)
			;;
	esac
	if [[ $TARGET_ENVIRONMENT_TYPE == "laptop" ]]; then
		enable_service_if_present tlp.service
		enable_service_if_present acpid.service
	fi
}

run_postinstall_service_enablement() {
	log_chroot_step "Enabling post-install services"
	systemctl set-default graphical.target || true
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

	case $TARGET_DISPLAY_MANAGER in
		greetd)
			systemctl disable sddm.service 2>/dev/null || true
			systemctl disable display-manager.service 2>/dev/null || true
			ensure_greetd_ready || exit 1
			echo "[DEBUG] Enabling greetd.service"
			if ! systemctl enable greetd.service; then
				echo "[FAIL] systemctl enable greetd.service failed"
				exit 1
			fi
			if ! systemctl is-enabled greetd.service >/dev/null 2>&1; then
				echo "[FAIL] greetd.service is not enabled after configuration"
				exit 1
			fi
			echo "[DEBUG] greetd.service enabled successfully"
			;;
		sddm)
			systemctl disable greetd.service 2>/dev/null || true
			systemctl disable display-manager.service 2>/dev/null || true
			enable_service_if_present sddm.service
			;;
		none)
			systemctl disable greetd.service 2>/dev/null || true
			systemctl disable sddm.service 2>/dev/null || true
			;;
		*)
			;;
	esac

	if [[ $TARGET_DESKTOP_PROFILE != "none" ]]; then
		enable_service_if_present bluetooth.service
	fi

	if [[ $TARGET_SNAPSHOT_PROVIDER == "snapper" ]]; then
		enable_service_if_present snapper-timeline.timer
		enable_service_if_present snapper-cleanup.timer
	fi

	configure_vm_services
}
EOF
}