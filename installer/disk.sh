#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=installer/ui.sh
source "$SCRIPT_DIR/ui.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh"
# shellcheck source=installer/modules/system.sh
source "$SCRIPT_DIR/modules/system.sh"
# shellcheck source=installer/modules/detect.sh
source "$SCRIPT_DIR/modules/detect.sh"
# shellcheck source=installer/modules/disk/layout.sh
source "$SCRIPT_DIR/modules/disk/layout.sh"
# shellcheck source=installer/modules/disk/space.sh
source "$SCRIPT_DIR/modules/disk/space.sh"
# shellcheck source=installer/modules/disk/manager.sh
source "$SCRIPT_DIR/modules/disk/manager.sh"

get_archiso_boot_disk() {
	local boot_source
	local parent_disk

	boot_source="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
	if [[ -z $boot_source || ! -b $boot_source ]]; then
		return 1
	fi

	parent_disk="$(lsblk -ndo PKNAME "$boot_source" 2>/dev/null || true)"
	if [[ -n $parent_disk ]]; then
		printf '/dev/%s\n' "$parent_disk"
		return 0
	fi

	printf '%s\n' "$boot_source"
}

disk_details() {
	local disk=${1:?disk is required}

	lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL "$disk" 2>/dev/null
}

list_disks() {
	local archiso_disk
	local name
	local type
	local model
	local partitions
	local size_gib
	local label
	local alerts

	archiso_disk="$(get_archiso_boot_disk 2>/dev/null || true)"

	while read -r name _ type; do
		[[ -n $name && -n $type ]] || continue

		[[ $type == "disk" ]] || continue
		[[ -n $archiso_disk && $name == "$archiso_disk" ]] && continue

		model="$(disk_model_value "$name")"
		size_gib="$(disk_size_gib "$name")"
		label="$(disk_label_value "$name")"
		alerts="$(detect_disk_os_presence "$name")"
		partitions="$(disk_partition_summary "$name")"

		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$size_gib" "$model" "$label" "$alerts" "$partitions"
	done < <(lsblk -dnpr -o NAME,SIZE,TYPE 2>/dev/null)
}

select_disk() {
	local rows
	local args=()
	local row
	local disk_name
	local disk_size
	local disk_model
	local disk_label
	local disk_alerts_value
	local disk_partitions
	local selected_disk
	local boot_mode
	local strategy
	local status
	local layout_state=""
	local -a strategy_args=()

	mapfile -t rows < <(list_disks)
	if [[ ${#rows[@]} -eq 0 ]]; then
		error_box "No Disks Found" "No installable block devices were detected. The live ISO boot device is excluded automatically for safety."
		return 1
	fi

	for row in "${rows[@]}"; do
		IFS=$'\t' read -r disk_name disk_size disk_model disk_label disk_alerts_value disk_partitions <<< "$row"
		args+=("$disk_name" "$disk_size | $disk_model | label=$disk_label | $disk_alerts_value | $disk_partitions")
	done

	menu "Disk Selection" "Choose a disk to manage for installation.\n\nThe installer will show the detected partitions and let you choose a safe strategy next." 20 100 10 "${args[@]}"
	selected_disk="$DIALOG_RESULT"
	status=$DIALOG_STATUS
	boot_mode="$(state_or_default "BOOT_MODE" "$(detect_boot_mode 2>/dev/null || printf 'bios')")"

	case $status in
		0)
			show_disk_analysis "$selected_disk"
			layout_state="$(disk_layout_state "$selected_disk")"
			strategy_args=(
				"wipe" "Full disk wipe and automatic partitioning"
			)
			if [[ $layout_state == "empty" || $layout_state == "corrupt" || $layout_state == "unreadable" ]]; then
				strategy_args+=("initialize" "Initialize disk (create GPT)")
			fi
			strategy_args+=(
				"free-space" "Create Linux partitions in the largest free-space region"
				"dual-boot" "Use free space while preserving detected Windows partitions"
				"manual" "Open the manual partition editor and select partitions"
				"back" "Return to disk selection"
			)
			menu "Disk Strategy" "Choose how to use $selected_disk.\n\nBoot mode: $boot_mode\nStatus: $(disk_layout_message "$selected_disk")\nAlerts: $(disk_alerts "$selected_disk")" 20 90 10 "${strategy_args[@]}"
			strategy="$DIALOG_RESULT"
			case $DIALOG_STATUS in
				0)
					case $strategy in
						wipe)
							prepare_full_wipe_install "$selected_disk" "$boot_mode" || true
							;;
						initialize)
							initialize_disk_dialog "$selected_disk" || true
							;;
						free-space)
							prepare_free_space_install "$selected_disk" "$boot_mode" "free-space" || true
							;;
						dual-boot)
							prepare_free_space_install "$selected_disk" "$boot_mode" "dual-boot" || true
							;;
						manual)
							manual_partition_editor "$selected_disk" "$boot_mode" || true
							;;
						*)
							return 0
							;;
					esac
					;;
				*)
					return 0
					;;
			esac
			;;
		1|255)
			return "$status"
			;;
		*)
			error_box "Selection Failed" "Disk selection returned an unexpected dialog status: $status"
			return "$status"
			;;
	esac
}

current_disk_label() {
	local selected_disk
	local scenario

	if selected_disk="$(get_state "DISK" 2>/dev/null)"; then
		scenario="$(get_state "INSTALL_SCENARIO" 2>/dev/null || printf 'unset')"
		printf '%s (%s)\n' "$selected_disk" "$scenario"
		return 0
	fi

	printf 'Not selected\n'
	return 1
}