#!/usr/bin/env bash

estimate_target_required_space_mib() {
	local desktop_profile=${1:-none}
	local filesystem=${2:-ext4}
	local required_mib=8192

	case $desktop_profile in
		kde)
			required_mib=20480
			;;
		*)
			required_mib=8192
			;;
	esac

	if [[ $filesystem == "btrfs" ]]; then
		required_mib=$((required_mib + 1024))
	fi

	required_mib=$((required_mib + 1024))

	printf '%s\n' "$required_mib"
}

target_available_space_mib() {
	local mount_point=${1:-/mnt}

	df -Pm "$mount_point" 2>/dev/null | awk 'NR==2 {print $4}'
}

ensure_target_has_space() {
	local mount_point=${1:?mount point is required}
	local required_mib=${2:?required space is required}
	local available_mib=""
	local df_line=""

	available_mib="$(target_available_space_mib "$mount_point" || true)"
	df_line="$(df -h "$mount_point" 2>/dev/null | awk 'NR==2 {print $0}' || true)"

	if [[ ! ${available_mib:-} =~ ^[0-9]+$ ]]; then
		printf 'Could not determine available space for %s\n' "$mount_point" >&2
		[[ -n $df_line ]] && printf '%s\n' "$df_line" >&2
		return 1
	fi

	if (( available_mib < required_mib )); then
		printf 'Insufficient free space on %s. Required: %s MiB, available: %s MiB\n' "$mount_point" "$required_mib" "$available_mib" >&2
		[[ -n $df_line ]] && printf '%s\n' "$df_line" >&2
		return 1
	fi

	return 0
}