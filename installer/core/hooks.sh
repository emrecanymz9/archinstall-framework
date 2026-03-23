#!/usr/bin/env bash

declare -ag ARCHINSTALL_PLUGIN_PACKAGES=()
declare -ag ARCHINSTALL_PLUGIN_CHROOT_SNIPPETS=()
declare -ag ARCHINSTALL_HOOK_PRE_DISK=()
declare -ag ARCHINSTALL_HOOK_POST_DISK=()
declare -ag ARCHINSTALL_HOOK_PRE_INSTALL=()
declare -ag ARCHINSTALL_HOOK_POST_INSTALL=()
declare -ag ARCHINSTALL_HOOK_POST_CHROOT=()
declare -ag ARCHINSTALL_MENU_MAIN=()
declare -ag ARCHINSTALL_MENU_DISK=()
declare -ag ARCHINSTALL_MENU_INSTALL=()

hook_array_name() {
	case ${1:-} in
		pre_disk)
			printf 'ARCHINSTALL_HOOK_PRE_DISK\n'
			;;
		post_disk)
			printf 'ARCHINSTALL_HOOK_POST_DISK\n'
			;;
		pre_install)
			printf 'ARCHINSTALL_HOOK_PRE_INSTALL\n'
			;;
		post_install)
			printf 'ARCHINSTALL_HOOK_POST_INSTALL\n'
			;;
		post_chroot)
			printf 'ARCHINSTALL_HOOK_POST_CHROOT\n'
			;;
		*)
			return 1
			;;
	esac
}

register_hook() {
	local hook_name=${1:?hook name is required}
	local function_name=${2:?function name is required}
	local array_name=""
	local -n hook_ref
	local existing=""

	array_name="$(hook_array_name "$hook_name")" || return 1
	if ! declare -F "$function_name" >/dev/null 2>&1; then
		return 1
	fi

	hook_ref=$array_name
	for existing in "${hook_ref[@]}"; do
		if [[ $existing == "$function_name" ]]; then
			return 0
		fi
	done
	hook_ref+=("$function_name")
}

run_hooks() {
	local hook_name=${1:?hook name is required}
	local array_name=""
	local hook_function=""
	local hook_status=0
	local -n hook_ref

	shift
	array_name="$(hook_array_name "$hook_name")" || return 0
	hook_ref=$array_name

	for hook_function in "${hook_ref[@]}"; do
		if ! declare -F "$hook_function" >/dev/null 2>&1; then
			continue
		fi
		if ! "$hook_function" "$@"; then
			hook_status=$?
			if declare -F log_debug >/dev/null 2>&1; then
				log_debug "Plugin hook failed: ${hook_name}/${hook_function} status=${hook_status}"
			else
				printf '[WARN] Plugin hook failed: %s/%s status=%s\n' "$hook_name" "$hook_function" "$hook_status" >&2
			fi
		fi
	done
	return 0
}

register_plugin_packages() {
	local package_name=""
	local existing=""
	local duplicate="false"

	for package_name in "$@"; do
		[[ -n $package_name ]] || continue
		duplicate="false"
		for existing in "${ARCHINSTALL_PLUGIN_PACKAGES[@]}"; do
			if [[ $existing == "$package_name" ]]; then
				duplicate="true"
				break
			fi
		done
		if [[ $duplicate != "true" ]]; then
			ARCHINSTALL_PLUGIN_PACKAGES+=("$package_name")
		fi
	done
}

list_plugin_packages() {
	printf '%s\n' "${ARCHINSTALL_PLUGIN_PACKAGES[@]}"
}

register_chroot_snippet() {
	local snippet=${1:-}
	[[ -n $snippet ]] || return 0
	ARCHINSTALL_PLUGIN_CHROOT_SNIPPETS+=("$snippet")
}

emit_chroot_snippets() {
	local snippet=""
	for snippet in "${ARCHINSTALL_PLUGIN_CHROOT_SNIPPETS[@]}"; do
		printf '%s\n' "$snippet"
	done
}

menu_array_name() {
	case ${1:-} in
		main)
			printf 'ARCHINSTALL_MENU_MAIN\n'
			;;
		disk)
			printf 'ARCHINSTALL_MENU_DISK\n'
			;;
		install)
			printf 'ARCHINSTALL_MENU_INSTALL\n'
			;;
		*)
			return 1
			;;
	esac
}

register_menu_entry() {
	local menu_name=${1:?menu name is required}
	local entry_id=${2:?entry id is required}
	local entry_label=${3:?entry label is required}
	local handler_name=${4:?handler name is required}
	local array_name=""
	local entry_record=""
	local existing=""
	local -n menu_ref

	array_name="$(menu_array_name "$menu_name")" || return 1
	if ! declare -F "$handler_name" >/dev/null 2>&1; then
		return 1
	fi

	menu_ref=$array_name
	entry_record="$entry_id	$entry_label	$handler_name"
	for existing in "${menu_ref[@]}"; do
		if [[ $existing == $entry_record ]]; then
			return 0
		fi
	done
	menu_ref+=("$entry_record")
}

emit_menu_entries() {
	local menu_name=${1:?menu name is required}
	local array_name=""
	local entry_record=""
	local entry_id=""
	local entry_label=""
	local handler_name=""
	local -n menu_ref

	array_name="$(menu_array_name "$menu_name")" || return 0
	menu_ref=$array_name
	for entry_record in "${menu_ref[@]}"; do
		IFS=$'\t' read -r entry_id entry_label handler_name <<< "$entry_record"
		[[ -n $entry_id && -n $entry_label ]] || continue
		printf '%s\n%s\n' "$entry_id" "$entry_label"
	done
}

run_menu_entry_handler() {
	local menu_name=${1:?menu name is required}
	local entry_id=${2:?entry id is required}
	local array_name=""
	local entry_record=""
	local record_id=""
	local record_label=""
	local handler_name=""
	local -n menu_ref

	array_name="$(menu_array_name "$menu_name")" || return 1
	menu_ref=$array_name
	for entry_record in "${menu_ref[@]}"; do
		IFS=$'\t' read -r record_id record_label handler_name <<< "$entry_record"
		if [[ $record_id != "$entry_id" ]]; then
			continue
		fi
		if ! declare -F "$handler_name" >/dev/null 2>&1; then
			return 1
		fi
		if ! "$handler_name"; then
			if declare -F log_debug >/dev/null 2>&1; then
				log_debug "Plugin menu handler failed: ${menu_name}/${entry_id}/${handler_name}"
			else
				printf '[WARN] Plugin menu handler failed: %s/%s/%s\n' "$menu_name" "$entry_id" "$handler_name" >&2
			fi
		fi
		return 0
	done

	return 1
}