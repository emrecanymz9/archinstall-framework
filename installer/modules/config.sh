#!/usr/bin/env bash

INSTALL_CONFIG_JSON=${INSTALL_CONFIG_JSON:-/tmp/install_config.json}

install_config_escape() {
	local value=${1-}

	value=${value//\\/\\\\}
	value=${value//"/\\"}
	value=${value//$'\n'/\\n}
	value=${value//$'\r'/\\r}
	value=${value//$'\t'/\\t}
	printf '%s' "$value"
}

install_config_get_or_default() {
	local key=${1:?config key is required}
	local default_value=${2-}
	local value=""

	value="$(get_state "$key" 2>/dev/null || true)"
	if [[ -n $value ]]; then
		printf '%s\n' "$value"
		return 0
	fi

	printf '%s\n' "$default_value"
}

install_config_bool_json() {
	if declare -F flag_enabled >/dev/null 2>&1 && flag_enabled "${1:-false}"; then
		printf 'true'
		return 0
	fi

	case ${1:-false} in
		1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
			printf 'true'
			;;
		*)
			printf 'false'
			;;
	esac
}

sync_install_config_json() {
	local disk="$(install_config_get_or_default "DISK" "")"
	local disk_type="$(normalize_disk_type "$(install_config_get_or_default "DISK_TYPE" "unknown")")"
	local filesystem="$(install_config_get_or_default "FILESYSTEM" "ext4")"
	local boot_mode="$(install_config_get_or_default "BOOT_MODE" "auto")"
	local install_scenario="$(install_config_get_or_default "INSTALL_SCENARIO" "wipe")"
	local efi_part="$(install_config_get_or_default "EFI_PART" "")"
	local root_part="$(install_config_get_or_default "ROOT_PART" "")"
	local enable_luks="$(install_config_get_or_default "ENABLE_LUKS" "false")"
	local luks_mapper_name="$(install_config_get_or_default "LUKS_MAPPER_NAME" "cryptroot")"
	local snapshot_provider="$(install_config_get_or_default "SNAPSHOT_PROVIDER" "none")"
	local install_profile="$(install_config_get_or_default "INSTALL_PROFILE" "daily")"
	local desktop_profile="$(install_config_get_or_default "DESKTOP_PROFILE" "none")"
	local display_manager="$(install_config_get_or_default "DISPLAY_MANAGER" "none")"
	local display_mode="$(install_config_get_or_default "DISPLAY_MODE" "auto")"
	local greeter_frontend="$(install_config_get_or_default "GREETER_FRONTEND" "tuigreet")"
	local environment_vendor="$(install_config_get_or_default "ENVIRONMENT_VENDOR" "unknown")"
	local environment_type="$(install_config_get_or_default "ENVIRONMENT_TYPE" "unknown")"
	local cpu_vendor="$(install_config_get_or_default "CPU_VENDOR" "unknown")"
	local gpu_vendor="$(install_config_get_or_default "GPU_VENDOR" "generic")"
	local enable_zram="$(install_config_get_or_default "ENABLE_ZRAM" "false")"
	local secure_boot_mode="$(install_config_get_or_default "SECURE_BOOT_MODE" "disabled")"
	local luks_password_set=${INSTALL_LUKS_PASSWORD:+true}
	local tmp_file=""

	mkdir -p "$(dirname "$INSTALL_CONFIG_JSON")" || return 1
	tmp_file="$(mktemp "${INSTALL_CONFIG_JSON}.XXXXXX")" || return 1

	cat > "$tmp_file" <<EOF
{
  "disk": {
    "device": "$(install_config_escape "$disk")",
    "type": "$(install_config_escape "$disk_type")",
    "filesystem": "$(install_config_escape "$filesystem")",
    "bootMode": "$(install_config_escape "$boot_mode")",
    "scenario": "$(install_config_escape "$install_scenario")",
    "efiPartition": "$(install_config_escape "$efi_part")",
    "rootPartition": "$(install_config_escape "$root_part")"
  },
  "encryption": {
    "enabled": $(install_config_bool_json "$enable_luks"),
    "mapperName": "$(install_config_escape "$luks_mapper_name")",
    "passwordSet": $(install_config_bool_json "$luks_password_set")
  },
  "profile": {
    "install": "$(install_config_escape "$install_profile")",
    "desktop": "$(install_config_escape "$desktop_profile")",
    "displayManager": "$(install_config_escape "$display_manager")",
    "displayMode": "$(install_config_escape "$display_mode")",
    "greeterFrontend": "$(install_config_escape "$greeter_frontend")"
  },
  "runtime": {
    "environmentVendor": "$(install_config_escape "$environment_vendor")",
    "environmentType": "$(install_config_escape "$environment_type")",
    "cpu": "$(install_config_escape "$cpu_vendor")",
    "gpu": "$(install_config_escape "$gpu_vendor")"
  },
  "features": {
    "zram": $(install_config_bool_json "$enable_zram"),
    "secureBootMode": "$(install_config_escape "$secure_boot_mode")",
    "snapshotProvider": "$(install_config_escape "$snapshot_provider")"
  }
}
EOF

	mv "$tmp_file" "$INSTALL_CONFIG_JSON"
	if declare -F log_debug >/dev/null 2>&1; then
		log_debug "Install config synced to $INSTALL_CONFIG_JSON"
	fi
}

register_config_module() {
	archinstall_register_module "config" "Shared JSON install config" "sync_install_config_json"
}