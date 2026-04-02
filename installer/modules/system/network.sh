#!/usr/bin/env bash
# Phase 3 network module — package list and service enablement for NetworkManager + iwd

network_required_packages() {
	local -n package_ref=${1:?package reference is required}
	package_ref=(networkmanager iwd)
}

enable_network_services() {
	echo "[STEP] Enabling network services"
	systemctl enable NetworkManager.service 2>/dev/null || true
	# iwd is used as the Wi-Fi backend for NetworkManager; enable it alongside
	systemctl enable iwd.service 2>/dev/null || true
}
