#!/usr/bin/env bash

ARCHINSTALL_REGISTERED_MODULES=${ARCHINSTALL_REGISTERED_MODULES:-}

archinstall_module_registered() {
	local module_name=${1:?module name is required}
	local line=""

	while IFS= read -r line; do
		[[ -n $line ]] || continue
		if [[ ${line%%$'|'*} == "$module_name" ]]; then
			return 0
		fi
	done <<< "$ARCHINSTALL_REGISTERED_MODULES"

	return 1
}

archinstall_register_module() {
	local module_name=${1:?module name is required}
	local module_description=${2:-}
	local module_runner=${3:-}

	if archinstall_module_registered "$module_name"; then
		return 0
	fi

	ARCHINSTALL_REGISTERED_MODULES+="${module_name}|${module_description}|${module_runner}"$'\n'
	if declare -F log_debug >/dev/null 2>&1; then
		log_debug "Registered module: $module_name"
	fi
}

archinstall_list_modules() {
	printf '%s' "$ARCHINSTALL_REGISTERED_MODULES"
}

archinstall_run_module() {
	local module_name=${1:?module name is required}
	local line=""
	local runner=""

	shift
	while IFS= read -r line; do
		[[ -n $line ]] || continue
		if [[ ${line%%$'|'*} != "$module_name" ]]; then
			continue
		fi
		runner="$(printf '%s' "$line" | awk -F'|' '{print $3}')"
		if [[ -n $runner ]] && declare -F "$runner" >/dev/null 2>&1; then
			"$runner" "$@"
			return $?
		fi
		return 1
	done <<< "$ARCHINSTALL_REGISTERED_MODULES"

	return 1
}

archinstall_register_builtin_modules() {
	local register_fn=""
	local -a register_functions=(
		register_config_module
		register_packages_module
		register_hardware_module
		register_luks_module
		register_snapshots_module
	)

	for register_fn in "${register_functions[@]}"; do
		if declare -F "$register_fn" >/dev/null 2>&1; then
			"$register_fn" || true
		fi
		done
}