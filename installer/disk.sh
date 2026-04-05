#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=installer/ui/dialog.sh
source "$SCRIPT_DIR/ui/dialog.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh" >/dev/null 2>&1
# shellcheck source=installer/core/system.sh
source "$SCRIPT_DIR/core/system.sh" >/dev/null 2>&1
# shellcheck source=installer/core/detect.sh
source "$SCRIPT_DIR/core/detect.sh" >/dev/null 2>&1
# shellcheck source=installer/core/disk/layout.sh
source "$SCRIPT_DIR/core/disk/layout.sh" >/dev/null 2>&1
# shellcheck source=installer/core/disk/space.sh
source "$SCRIPT_DIR/core/disk/space.sh" >/dev/null 2>&1
# shellcheck source=installer/core/disk/manager.sh
source "$SCRIPT_DIR/core/disk/manager.sh" >/dev/null 2>&1

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
	local transport
	local disk_type

	archiso_disk="$(get_archiso_boot_disk 2>/dev/null || true)"

	while read -r name _ type; do
		[[ -n $name && -n $type ]] || continue

		[[ $type == "disk" ]] || continue
		[[ -n $archiso_disk && $name == "$archiso_disk" ]] && continue

		model="$(disk_model_value "$name")"
		transport="$(disk_transport_label "$(disk_transport_value "$name")")"
		disk_type="$(disk_type_label "$(detect_disk_type "$name" 2>/dev/null || printf 'hdd')")"
		size_gib="$(disk_size_gib "$name")"
		label="$(disk_label_value "$name")"
		alerts="$(detect_disk_os_presence "$name")"
		partitions="$(disk_partition_summary "$name")"

		printf '%s\t%s\t%s (%s, %s)\t%s\t%s\t%s\n' "$name" "$size_gib" "$model" "$transport" "$disk_type" "$label" "$alerts" "$partitions"
	done < <(lsblk -dnpr -o NAME,SIZE,TYPE 2>/dev/null)
}

clear_saved_partition_state() {
	unset_state "INSTALL_SCENARIO"
	unset_state "FORMAT_ROOT"
	unset_state "FORMAT_EFI"
	unset_state "EFI_PART"
	unset_state "ROOT_PART"
}

persist_selected_disk_state() {
	local selected_disk=${1:?selected disk is required}

	set_state "DISK" "$selected_disk" || return 1
	set_state "DISK_MODEL" "$(disk_model_value "$selected_disk")" || return 1
	set_state "DISK_TRANSPORT" "$(disk_transport_value "$selected_disk")" || return 1
	set_state "DISK_TYPE" "$(detect_disk_type "$selected_disk" 2>/dev/null || printf 'hdd')" || return 1
	clear_saved_partition_state
	return 0
}

select_install_target_disk() {
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
	local status

	mapfile -t rows < <(list_disks)
	if [[ ${#rows[@]} -eq 0 ]]; then
		error_box "No Disks Found" "No installable block devices were detected. The live ISO boot device is excluded automatically for safety."
		return 1
	fi

	for row in "${rows[@]}"; do
		IFS=$'\t' read -r disk_name disk_size disk_model disk_label disk_alerts_value disk_partitions <<< "$row"
		args+=("$disk_name" "$disk_size | $disk_model | label=$disk_label | $disk_alerts_value | $disk_partitions")
	done

	menu "Disk" "Choose the disk you want to install to.\n\nTip: this screen only selects the device. Partitioning happens on the next screen." 20 100 10 "${args[@]}"
	selected_disk="$DIALOG_RESULT"
	status=$DIALOG_STATUS

	case $status in
		0)
			persist_selected_disk_state "$selected_disk" || return 1
			show_disk_analysis "$selected_disk"
			return 0
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

select_partition_strategy_for_disk() {
	local selected_disk=${1:-$(get_state "DISK" 2>/dev/null || printf '')}
	local boot_mode=""
	local strategy=""
	local action_status=1
	local layout_state=""
	local -a strategy_args=()

	if [[ -z $selected_disk ]]; then
		msg "Disk Required" "Choose a target disk before opening the partition screen."
		return 1
	fi

	boot_mode="$(state_or_default "BOOT_MODE" "$(detect_boot_mode 2>/dev/null || printf 'bios')")"
	show_disk_analysis "$selected_disk"
	layout_state="$(disk_layout_state "$selected_disk")"
	strategy_args=(
		"wipe" "Auto partition (recommended): erase the disk and create the guided layout"
	)
	if [[ $layout_state == "empty" || $layout_state == "corrupt" || $layout_state == "unreadable" ]]; then
		strategy_args+=("initialize" "Initialize the disk label before partitioning")
	fi
	strategy_args+=(
		"free-space" "Use available free space on the selected disk"
		"dual-boot" "Preserve detected Windows partitions and use free space"
		"manual" "Reuse or choose prepared partitions yourself"
		"back" "Return to the previous menu"
	)

	menu "Partition" "Choose how to use $selected_disk.\n\nTip: pick wipe only when you want the installer to erase the whole disk.\n\nBoot mode: $boot_mode\nStatus: $(disk_layout_message "$selected_disk")\nAlerts: $(disk_alerts "$selected_disk")" 20 94 10 "${strategy_args[@]}"
	strategy="$DIALOG_RESULT"
	case $DIALOG_STATUS in
		0)
			case $strategy in
				wipe)
					prepare_full_wipe_install "$selected_disk" "$boot_mode"
					action_status=$?
					;;
				initialize)
					initialize_disk_dialog "$selected_disk"
					action_status=$?
					;;
				free-space)
					prepare_free_space_install "$selected_disk" "$boot_mode" "free-space"
					action_status=$?
					;;
				dual-boot)
					prepare_free_space_install "$selected_disk" "$boot_mode" "dual-boot"
					action_status=$?
					;;
				manual)
					manual_partition_editor "$selected_disk" "$boot_mode"
					action_status=$?
					;;
				back)
					return 1
					;;
				*)
					return 1
					;;
			esac
			return "$action_status"
			;;
		*)
			return 1
			;;
	esac
}

select_disk() {
	select_install_target_disk || return $?
	select_partition_strategy_for_disk "$(get_state "DISK" 2>/dev/null || printf '')"
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