#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=installer/ui.sh
source "$SCRIPT_DIR/ui.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh"

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

list_disks() {
	local archiso_disk
	local name
	local size
	local type
	local model

	archiso_disk="$(get_archiso_boot_disk 2>/dev/null || true)"

	while read -r name size type; do
		[[ -n $name && -n $size && -n $type ]] || continue

		[[ $type == "disk" ]] || continue
		[[ -n $archiso_disk && $name == "$archiso_disk" ]] && continue

		model="$(lsblk -dnro MODEL "$name" 2>/dev/null || true)"
		model=${model//$'\t'/ }
		model=${model//$'\n'/ }
		[[ -n $model ]] || model="Unknown model"

		printf '%s\t%s\t%s\n' "$name" "$size" "$model"
	done < <(lsblk -dnpr -o NAME,SIZE,TYPE 2>/dev/null)
}

select_disk() {
	local rows
	local args=()
	local row
	local disk_name
	local disk_size
	local disk_model
	local selected_disk
	local status

	mapfile -t rows < <(list_disks)
	if [[ ${#rows[@]} -eq 0 ]]; then
		error_box "No Disks Found" "No installable block devices were detected. The live ISO boot device is excluded automatically for safety."
		return 1
	fi

	for row in "${rows[@]}"; do
		IFS=$'\t' read -r disk_name disk_size disk_model <<< "$row"
		args+=("$disk_name" "$disk_size - $disk_model")
	done

	selected_disk="$(menu "Disk Selection" "Choose the target disk for installation." 18 76 10 "${args[@]}")"
	status=$?

	case $status in
		0)
			set_state "DISK" "$selected_disk"
			msg "Disk Selected" "Installation target saved as:\n\n$selected_disk"
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

	if selected_disk="$(get_state "DISK" 2>/dev/null)"; then
		printf '%s\n' "$selected_disk"
		return 0
	fi

	printf 'Not selected\n'
	return 1
}