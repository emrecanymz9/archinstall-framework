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

disk_partition_summary() {
	local disk=${1:?disk is required}
	local summary

	summary="$(lsblk -lnpo NAME,SIZE,FSTYPE,TYPE "$disk" 2>/dev/null | awk '
		$4 == "part" {
			fstype = ($3 == "" ? "unknown" : $3)
			parts[++count] = $1 " " $2 " " fstype
		}
		END {
			if (count == 0) {
				print "No existing partitions"
				exit
			}

			for (index = 1; index <= count; index++) {
				printf "%s%s", parts[index], (index < count ? "; " : "")
			}
		}
	')"

	printf '%s\n' "$summary"
}

disk_details() {
	local disk=${1:?disk is required}

	lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL "$disk" 2>/dev/null
}

list_disks() {
	local archiso_disk
	local name
	local size
	local type
	local model
	local partitions

	archiso_disk="$(get_archiso_boot_disk 2>/dev/null || true)"

	while read -r name size type; do
		[[ -n $name && -n $size && -n $type ]] || continue

		[[ $type == "disk" ]] || continue
		[[ -n $archiso_disk && $name == "$archiso_disk" ]] && continue

		model="$(lsblk -dnro MODEL "$name" 2>/dev/null || true)"
		model=${model//$'\t'/ }
		model=${model//$'\n'/ }
		[[ -n $model ]] || model="Unknown model"
		partitions="$(disk_partition_summary "$name")"

		printf '%s\t%s\t%s\t%s\n' "$name" "$size" "$model" "$partitions"
	done < <(lsblk -dnpr -o NAME,SIZE,TYPE 2>/dev/null)
}

confirm_disk_selection() {
	local disk=${1:?disk is required}
	local details

	details="$(disk_details "$disk")"
	confirm "Confirm Disk Selection" "Selected full disk:\n\n$disk\n\nCurrent layout:\n$details\n\nThis installer currently uses full-disk installation only. Continuing later will erase existing partitions and data on this disk. Save this disk as the installation target?" 20 76
}

select_disk() {
	local rows
	local args=()
	local row
	local disk_name
	local disk_size
	local disk_model
	local disk_partitions
	local selected_disk
	local status

	mapfile -t rows < <(list_disks)
	if [[ ${#rows[@]} -eq 0 ]]; then
		error_box "No Disks Found" "No installable block devices were detected. The live ISO boot device is excluded automatically for safety."
		return 1
	fi

	for row in "${rows[@]}"; do
		IFS=$'\t' read -r disk_name disk_size disk_model disk_partitions <<< "$row"
		args+=("$disk_name" "$disk_size - $disk_model | $disk_partitions")
	done

	menu "Disk Selection" "Choose the full disk target for installation." 18 90 10 "${args[@]}"
	selected_disk="$DIALOG_RESULT"
	status=$DIALOG_STATUS

	case $status in
		0)
			if ! confirm_disk_selection "$selected_disk"; then
				return 0
			fi

			set_state "DISK" "$selected_disk"
			unset_state "EFI_PART"
			unset_state "ROOT_PART"
			msg "Disk Selected" "Installation target saved as:\n\n$selected_disk\n\nThe installer will use the whole disk."
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