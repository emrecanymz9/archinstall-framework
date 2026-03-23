#!/usr/bin/env bash

disk_size_gib() {
	local disk=${1:?disk is required}
	local size_bytes=""

	size_bytes="$(lsblk -dnbo SIZE "$disk" 2>/dev/null || true)"
	if [[ ! $size_bytes =~ ^[0-9]+$ ]]; then
		printf 'Unknown\n'
		return 0
	fi

	awk -v size_bytes="$size_bytes" 'BEGIN { printf "%.1f GiB\n", size_bytes / 1024 / 1024 / 1024 }'
}

disk_label_value() {
	local disk=${1:?disk is required}
	local label=""

	label="$(lsblk -dnro LABEL "$disk" 2>/dev/null | head -n 1 || true)"
	if [[ -z $label ]]; then
		label="$(blkid -o value -s LABEL "$disk" 2>/dev/null || true)"
	fi
	printf '%s\n' "${label:-Unlabeled}"
}

disk_alerts() {
	local disk=${1:?disk is required}
	local has_windows="false"
	local has_linux="false"
	local fstype=""
	local partlabel=""
	local row=""
	local alerts=()

	while IFS=$'\t' read -r _ _ fstype partlabel; do
		case ${fstype,,}:${partlabel,,} in
			ntfs:*|*:*windows*|*:*microsoft*)
				has_windows="true"
				;;
			ext4:*|btrfs:*|xfs:*|f2fs:*|swap:*|*:*linux*)
				has_linux="true"
				;;
		esac
	done < <(lsblk -lnpo NAME,SIZE,FSTYPE,PARTLABEL "$disk" 2>/dev/null)

	[[ $has_windows == "true" ]] && alerts+=("Windows detected")
	[[ $has_linux == "true" ]] && alerts+=("Linux partitions detected")
	if [[ ${#alerts[@]} -eq 0 ]]; then
		printf 'No OS signatures detected\n'
		return 0
	fi

	printf '%s\n' "$(printf '%s; ' "${alerts[@]}")" | sed 's/; $//' 
}

disk_partition_rows() {
	local disk=${1:?disk is required}

	lsblk -lnpo NAME,SIZE,FSTYPE,PARTLABEL,LABEL,TYPE,MOUNTPOINTS "$disk" 2>/dev/null | awk '
		$6 == "part" {
			fstype = ($3 == "" ? "unknown" : $3)
			partlabel = ($4 == "" ? "-" : $4)
			label = ($5 == "" ? "-" : $5)
			mountpoint = ($7 == "" ? "-" : $7)
			printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, fstype, partlabel, label, mountpoint
		}
	'
}

disk_partition_summary() {
	local disk=${1:?disk is required}
	local row=""
	local path=""
	local size=""
	local fstype=""
	local partlabel=""
	local label=""
	local mountpoint=""
	local summaries=()

	while IFS=$'\t' read -r path size fstype partlabel label mountpoint; do
		summaries+=("${path##*/} ${size} ${fstype} ${partlabel} ${label}")
	done < <(disk_partition_rows "$disk")

	if [[ ${#summaries[@]} -eq 0 ]]; then
		printf 'No existing partitions\n'
		return 0
	fi

	printf '%s\n' "$(printf '%s; ' "${summaries[@]}")" | sed 's/; $//' 
}

largest_free_region() {
	local disk=${1:?disk is required}

	parted -ms "$disk" unit MiB print free 2>/dev/null | awk -F: '
		$1 ~ /^[0-9]+$/ && $5 == "free;" {
			start = $2
			end = $3
			size = $4
			gsub(/MiB/, "", start)
			gsub(/MiB/, "", end)
			gsub(/MiB/, "", size)
			if (size + 0 > max_size + 0) {
				max_size = size
				max_start = start
				max_end = end
			}
		}
		END {
			if (max_size + 0 > 0) {
				printf "%d\t%d\t%d\n", max_start, max_end, max_size
			}
		}
	'
}

partition_name_list() {
	local disk=${1:?disk is required}
	lsblk -lnpo NAME,TYPE "$disk" 2>/dev/null | awk '$2 == "part" { print $1 }'
}

find_new_partitions() {
	local before_list=${1:-}
	local after_list=${2:-}
	local item=""
	local line=""

	while IFS= read -r line; do
		[[ -n $line ]] || continue
		if ! grep -Fxq "$line" <<< "$before_list"; then
			printf '%s\n' "$line"
		fi
	done <<< "$after_list"
}

find_existing_efi_partition() {
	local disk=${1:?disk is required}
	local part=""
	local fstype=""
	local partlabel=""

	while IFS=$'\t' read -r part _ fstype partlabel _ _; do
		case ${fstype,,}:${partlabel,,}:${part##*/} in
			vfat:*esp*:*|fat32:*esp*:*|vfat:*efi*:*|fat32:*efi*:*)
				printf '%s\n' "$part"
				return 0
				;;
			vfat:*:*|fat32:*:*)
				printf '%s\n' "$part"
				return 0
				;;
		esac
	done < <(disk_partition_rows "$disk")

	return 1
}

partition_menu_entries() {
	local disk=${1:?disk is required}
	local role=${2:-root}
	local row=""
	local path=""
	local size=""
	local fstype=""
	local partlabel=""
	local label=""
	local mountpoint=""

	while IFS=$'\t' read -r path size fstype partlabel label mountpoint; do
		if [[ $role == "efi" ]]; then
			case ${fstype,,} in
				vfat|fat32|unknown)
					;;
				*)
					continue
					;;
			esac
		fi
		printf '%s\n%s\n' "$path" "$size | fs=$fstype | partlabel=$partlabel | label=$label | mount=$mountpoint"
	done < <(disk_partition_rows "$disk")
}

show_disk_analysis() {
	local disk=${1:?disk is required}
	local model=""
	local size_gib=""
	local label=""
	local alerts=""
	local partitions=""

	model="$(lsblk -dnro MODEL "$disk" 2>/dev/null || printf 'Unknown model')"
	size_gib="$(disk_size_gib "$disk")"
	label="$(disk_label_value "$disk")"
	alerts="$(disk_alerts "$disk")"
	partitions="$(disk_partition_summary "$disk")"

	msg "Disk Analysis" "Disk: $disk\nModel: $model\nSize: $size_gib\nLabel: $label\nAlerts: $alerts\n\nPartitions:\n$partitions" 20 90
}

prepare_install_state() {
	local disk=${1:?disk is required}
	local scenario=${2:?scenario is required}
	local root_partition=${3:-}
	local efi_partition=${4:-}
	local format_root=${5:-true}
	local format_efi=${6:-false}

	set_state "DISK" "$disk" || return 1
	set_state "INSTALL_SCENARIO" "$scenario" || return 1
	set_state "FORMAT_ROOT" "$format_root" || return 1
	set_state "FORMAT_EFI" "$format_efi" || return 1
	if [[ -n $root_partition ]]; then
		set_state "ROOT_PART" "$root_partition" || return 1
	else
		unset_state "ROOT_PART" || return 1
	fi
	if [[ -n $efi_partition ]]; then
		set_state "EFI_PART" "$efi_partition" || return 1
	else
		unset_state "EFI_PART" || return 1
	fi
}

prepare_full_wipe_install() {
	local disk=${1:?disk is required}
	local boot_mode=${2:-bios}

	if ! confirm "Full Disk Wipe" "This will use the entire disk and recreate the partition table.\n\nDisk: $disk\nBoot mode: $boot_mode\n\nAll existing partitions will be lost. Continue?" 16 76; then
		return 1
	fi

	prepare_install_state "$disk" "wipe" "" "" "true" "true"
	msg "Disk Strategy Saved" "Strategy: full disk wipe\nDisk: $disk\n\nThe executor will recreate the partition table during installation."
}

prepare_free_space_install() {
	local disk=${1:?disk is required}
	local boot_mode=${2:-bios}
	local scenario=${3:-free-space}
	local largest_region=""
	local start_mib=""
	local end_mib=""
	local size_mib=""
	local before_partitions=""
	local after_partitions=""
	local new_partitions=()
	local required_root_mib=""
	local required_total_mib=""
	local existing_efi=""
	local efi_partition=""
	local root_partition=""
	local efi_part_number=""
	local efi_start_mib=0
	local efi_end_mib=0
	local root_start_mib=0

	required_root_mib="$(estimate_target_required_space_mib "$(state_or_default "DESKTOP_PROFILE" "none")" "$(state_or_default "FILESYSTEM" "ext4")")"
	existing_efi="$(find_existing_efi_partition "$disk" || true)"
	required_total_mib=$required_root_mib
	if [[ $boot_mode == "uefi" && -z $existing_efi ]]; then
		required_total_mib=$((required_total_mib + 512))
	fi

	largest_region="$(largest_free_region "$disk")"
	if [[ -z $largest_region ]]; then
		warning_box "No Free Space" "No usable free-space region was detected on $disk. Use the manual partition editor if you want to resize or rearrange partitions first."
		return 1
	fi

	IFS=$'\t' read -r start_mib end_mib size_mib <<< "$largest_region"
	if (( size_mib < required_total_mib )); then
		warning_box "Insufficient Free Space" "Largest free region: ${size_mib} MiB\nRequired: ${required_total_mib} MiB\n\nUse Windows Disk Management, another tool, or the manual partition editor to free space safely."
		return 1
	fi

	if [[ $scenario == "dual-boot" ]]; then
		warning_box "Windows Installation Detected" "Windows signatures were detected on this disk.\n\nThe installer will avoid wiping the disk and will create Linux partitions only in existing free space."
	fi

	if ! confirm "Use Free Space" "Disk: $disk\nLargest free region: ${size_mib} MiB\nRoot filesystem requirement: ${required_root_mib} MiB\nExisting EFI: ${existing_efi:-none}\n\nCreate new Linux partitions in that free region now?" 18 78; then
		return 1
	fi

	before_partitions="$(partition_name_list "$disk")"
	if [[ $boot_mode == "uefi" && -z $existing_efi ]]; then
		efi_start_mib=$start_mib
		efi_end_mib=$((start_mib + 512))
		root_start_mib=$efi_end_mib
		parted -s "$disk" mkpart ARCH_EFI fat32 "${efi_start_mib}MiB" "${efi_end_mib}MiB" || return 1
	else
		root_start_mib=$start_mib
	fi
	parted -s "$disk" mkpart ARCH_ROOT ext4 "${root_start_mib}MiB" "${end_mib}MiB" || return 1
	partprobe "$disk" || return 1
	if command -v udevadm >/dev/null 2>&1; then
		udevadm settle || return 1
	fi
	after_partitions="$(partition_name_list "$disk")"
	mapfile -t new_partitions < <(find_new_partitions "$before_partitions" "$after_partitions")
	if [[ $boot_mode == "uefi" && -z $existing_efi ]]; then
		efi_partition=${new_partitions[0]:-}
		root_partition=${new_partitions[1]:-}
		efi_part_number="$(lsblk -dnro PARTN "$efi_partition" 2>/dev/null || true)"
		if [[ $efi_part_number =~ ^[0-9]+$ ]]; then
			parted -s "$disk" set "$efi_part_number" esp on 2>/dev/null || true
			parted -s "$disk" set "$efi_part_number" boot on 2>/dev/null || true
		fi
	else
		efi_partition=$existing_efi
		root_partition=${new_partitions[0]:-}
	fi

	if [[ -z $root_partition ]]; then
		error_box "Partition Creation Failed" "The root partition could not be identified after creating partitions on $disk."
		return 1
	fi

	prepare_install_state "$disk" "$scenario" "$root_partition" "$efi_partition" "true" "$(if [[ -n $existing_efi ]]; then printf 'false'; else printf 'true'; fi)"
	msg "Disk Strategy Saved" "Strategy: $scenario\nDisk: $disk\nRoot partition: $root_partition\nEFI partition: ${efi_partition:-not required}\n\nThe executor will reuse this layout instead of wiping the disk."
}

manual_partition_editor() {
	local disk=${1:?disk is required}
	local boot_mode=${2:-bios}
	local root_partition=""
	local efi_partition=""
	local format_efi="false"
	local -a root_entries=()
	local -a efi_entries=()

	clear_screen
	if command -v cfdisk >/dev/null 2>&1; then
		cfdisk "$disk"
	else
		parted "$disk"
	fi

	mapfile -t root_entries < <(partition_menu_entries "$disk" root)
	if [[ ${#root_entries[@]} -eq 0 ]]; then
		warning_box "No Partitions Available" "No partitions were found on $disk after leaving the manual editor. Create partitions first, then try again."
		return 1
	fi

	menu "Manual Root Partition" "Choose the root partition to use on $disk. The selected partition will be formatted for the new install." 18 88 10 "${root_entries[@]}"
	case $DIALOG_STATUS in
		0)
			root_partition="$DIALOG_RESULT"
			;;
		*)
			return 1
			;;
	esac

	if [[ $boot_mode == "uefi" ]]; then
		mapfile -t efi_entries < <(partition_menu_entries "$disk" efi)
		if [[ ${#efi_entries[@]} -eq 0 ]]; then
			warning_box "EFI Partition Required" "No EFI-compatible partition was detected on $disk. Create one in the manual editor or use the free-space workflow."
			return 1
		fi

		menu "Manual EFI Partition" "Choose the EFI system partition to use on $disk." 18 88 10 "${efi_entries[@]}"
		case $DIALOG_STATUS in
			0)
				efi_partition="$DIALOG_RESULT"
				;;
			*)
				return 1
				;;
		esac
		format_efi="$(select_boolean_value "EFI Formatting" "Format the selected EFI partition? Choose false when reusing a Windows or existing EFI partition." "false" "Format EFI" "Keep EFI contents")" || return 1
	fi

	prepare_install_state "$disk" "manual" "$root_partition" "$efi_partition" "true" "$format_efi"
	msg "Manual Layout Saved" "Disk: $disk\nRoot partition: $root_partition\nEFI partition: ${efi_partition:-not required}\nFormat EFI: $format_efi\n\nThe executor will reuse this manual layout."
}