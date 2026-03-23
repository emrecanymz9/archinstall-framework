#!/usr/bin/env bash

example_plugin_pre_install() {
	if declare -F log_debug >/dev/null 2>&1; then
		log_debug "Example plugin pre_install hook invoked"
	fi
	return 0
}

register_hook pre_install example_plugin_pre_install || true