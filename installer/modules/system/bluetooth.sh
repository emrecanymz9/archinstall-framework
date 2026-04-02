#!/usr/bin/env bash
# Phase 3 bluetooth module — package list and service enablement for BlueZ

bluetooth_required_packages() {
	local -n package_ref=${1:?package reference is required}
	package_ref=(bluez bluez-utils)
}

enable_bluetooth_service() {
	echo "[STEP] Enabling bluetooth"
	if systemctl list-unit-files bluetooth.service >/dev/null 2>&1; then
		systemctl enable bluetooth.service || true
	else
		echo "[WARN] bluetooth.service not present - skipping"
	fi
}
