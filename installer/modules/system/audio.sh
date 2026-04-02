#!/usr/bin/env bash
# Phase 3 audio module — package list and user-service enablement for PipeWire

audio_required_packages() {
	local -n package_ref=${1:?package reference is required}
	package_ref=(pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber)
}

enable_audio_services() {
	echo "[STEP] Enabling audio user services"
	# Enable PipeWire and WirePlumber for all users via the global systemd user preset
	install -d -m 0755 /etc/systemd/user/default.target.wants
	ln -sf /usr/lib/systemd/user/pipewire.service \
		/etc/systemd/user/default.target.wants/pipewire.service 2>/dev/null || true
	ln -sf /usr/lib/systemd/user/pipewire-pulse.service \
		/etc/systemd/user/default.target.wants/pipewire-pulse.service 2>/dev/null || true
	ln -sf /usr/lib/systemd/user/wireplumber.service \
		/etc/systemd/user/default.target.wants/wireplumber.service 2>/dev/null || true
}
