#!/usr/bin/env bash
# Phase 3 bluetooth module — package list and service enablement for BlueZ

bluetooth_required_packages() {
	local -n package_ref=${1:?package reference is required}
	package_ref=(bluez bluez-utils)
}

enable_bluetooth_service() {
	echo "[INFO] Bluetooth service enablement is handled by installer/postinstall/services.sh"
	return 0
}
