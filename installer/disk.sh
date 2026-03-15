#!/usr/bin/env bash
# installer/disk.sh – disk selection, install-mode, partitioning
set -Eeuo pipefail

# Exported after partitioning (consumed by luks.sh, filesystem.sh, limine.sh)
EFI_PART=""
ROOT_PART=""
NEW_ESP=false  # true when a new ESP was created (tells filesystem.sh to format it)

# Minimum recommended free space for the full stack (KDE + gaming + devtools)
readonly MIN_RECOMMENDED_GIB=80

# ---------------------------------------------------------------------------
# Helper: partition device name  (nvme/mmcblk use 'p' suffix)
# ---------------------------------------------------------------------------
part_dev() {
    local disk="$1" num="$2"
    if [[ "$disk" =~ (nvme|mmcblk) ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}

# ---------------------------------------------------------------------------
# list_disks  →  stdout lines: "name|size|model|serial"
# ---------------------------------------------------------------------------
list_disks() {
    lsblk -d -o NAME,SIZE,MODEL,SERIAL,TYPE --noheadings --bytes \
        | awk '$5 == "disk" { printf "%s|%s|%s|%s\n", $1, $2, $3, $4 }' \
        | while IFS='|' read -r name bytes model serial; do
            local gib
            gib=$(awk "BEGIN{printf \"%.1f GiB\", $bytes/1073741824}")
            printf "%s|%s|%s|%s\n" "$name" "$gib" "${model:-Unknown}" "${serial:-N/A}"
          done
}

# ---------------------------------------------------------------------------
# select_disk  →  sets TARGET_DISK, saves to state
# ---------------------------------------------------------------------------
select_disk() {
    local disks
    disks=$(list_disks)

    if [[ -z "$disks" ]]; then
        ui_msgbox "Error" "No installable disks detected."
        exit 1
    fi

    local menu_args=()
    while IFS='|' read -r name size model serial; do
        menu_args+=("$name" "${size}  ${model}  [S/N: ${serial}]")
    done <<< "$disks"

    local choice
    choice=$(ui_menu "Disk Selection" \
        "Select the disk to install Arch Linux on.\n\nWARNING: The next steps may erase data on the selected disk." \
        "${menu_args[@]}") || { clear; exit 0; }

    TARGET_DISK="/dev/${choice}"
    set_state_str "target_disk" "$TARGET_DISK"
    log_info "Target disk: $TARGET_DISK"

    # Show disk detail summary
    local detail
    detail=$(lsblk -o NAME,SIZE,FSTYPE,PARTLABEL,MOUNTPOINTS "$TARGET_DISK" 2>/dev/null || true)
    ui_msgbox "Disk Summary: $TARGET_DISK" \
        "You selected: $TARGET_DISK\n\nCurrent layout:\n\n${detail}\n\nThe next screens will let you choose how to use this disk."
}

# ---------------------------------------------------------------------------
# detect_free_segments  →  stdout lines: "start_MiB|end_MiB|size_MiB"
# ---------------------------------------------------------------------------
detect_free_segments() {
    local disk="$1"
    parted -m -s "$disk" unit MiB print free 2>/dev/null \
        | awk -F: '$5 == "free" {
            gsub("MiB","",$2); gsub("MiB","",$3); gsub("MiB","",$4)
            if ($4+0 > 100) printf "%s|%s|%s\n", $2, $3, $4
          }'
}

# ---------------------------------------------------------------------------
# detect_linux_partitions  →  stdout lines: "dev|size|fstype|label"
# ---------------------------------------------------------------------------
detect_linux_partitions() {
    local disk="$1"
    lsblk -lpno NAME,SIZE,FSTYPE,PARTLABEL "$disk" --noheadings \
        | awk '$3 ~ /^(ext4|btrfs|xfs|f2fs|swap|crypto_LUKS)$/ {
            printf "%s|%s|%s|%s\n", $1, $2, $3, ($4=="" ? "-" : $4)
          }'
}

# ---------------------------------------------------------------------------
# detect_windows  →  returns 0 if Windows detected on disk
# ---------------------------------------------------------------------------
detect_windows() {
    local disk="$1"
    lsblk -lpno FSTYPE "$disk" 2>/dev/null | grep -qi ntfs
}

# ---------------------------------------------------------------------------
# detect_existing_esp  →  stdout: device path of existing ESP, or empty
# ---------------------------------------------------------------------------
detect_existing_esp() {
    local disk="$1"
    lsblk -lpno NAME,PARTTYPE,FSTYPE "$disk" 2>/dev/null \
        | awk 'tolower($2) ~ /c12a7328|vfat/ && $3=="vfat" {print $1; exit}' \
        || lsblk -lpno NAME,FSTYPE "$disk" 2>/dev/null \
        | awk '$2=="vfat"{print $1; exit}'
}

# ---------------------------------------------------------------------------
# choose_install_mode  →  sets INSTALL_MODE, saves to state
# ---------------------------------------------------------------------------
choose_install_mode() {
    local disk="$1"
    local has_windows=false has_linux=false has_free=false
    local free_info="" linux_parts="" esp_exists=""

    # Check Windows
    detect_windows "$disk" && has_windows=true

    # Check Linux partitions
    linux_parts=$(detect_linux_partitions "$disk")
    [[ -n "$linux_parts" ]] && has_linux=true

    # Check free segments
    free_info=$(detect_free_segments "$disk")
    [[ -n "$free_info" ]] && has_free=true

    # Build context note
    local context_note=""
    "$has_windows" && context_note+="⚠  Windows partitions detected on this disk.\n"
    "$has_linux"   && context_note+="   Linux partition(s) found on this disk.\n"
    "$has_free"    && context_note+="   Unallocated free space found on this disk.\n"
    [[ -z "$context_note" ]] && context_note="   No Windows or Linux partitions detected.\n"

    local choice
    choice=$(ui_radiolist "Install Mode" \
        "${context_note}\nChoose how to install Arch Linux:" \
        "wipe"      "Use entire disk — WIPE everything and install"                "on" \
        "freespace" "Use unallocated free space — dual-boot safe"                  "off" \
        "reinstall" "Reinstall on existing Linux partition — wipe Linux only"      "off" \
    ) || { clear; exit 0; }

    # Validate mode availability
    case "$choice" in
        freespace)
            if ! "$has_free"; then
                ui_msgbox "No Free Space Found" \
"No unallocated free space was detected on $disk.\n\n\
To create free space for dual-booting:\n\
  1. Boot into Windows\n\
  2. Open 'Disk Management' (diskmgmt.msc)\n\
  3. Right-click your Windows partition → Shrink Volume\n\
  4. Reboot into the Arch ISO and re-run the installer.\n\n\
The installer will NEVER shrink NTFS partitions automatically."
                exit 0
            fi
            _show_free_segments "$disk" "$free_info"
            ;;
        reinstall)
            if ! "$has_linux"; then
                ui_msgbox "No Linux Partitions Found" \
                    "No Linux-compatible partitions were found on $disk.\n\nPlease choose a different install mode."
                choose_install_mode "$disk"
                return
            fi
            ;;
    esac

    INSTALL_MODE="$choice"
    set_state_str "install_mode" "$INSTALL_MODE"
    log_info "Install mode: $INSTALL_MODE"
}

# Internal: show free segment list and warn if too small
_show_free_segments() {
    local disk="$1" free_info="$2"
    local seg_list="" idx=1 total_free=0

    while IFS='|' read -r start end size_mib; do
        local size_gib
        size_gib=$(awk "BEGIN{printf \"%.1f\", $size_mib/1024}")
        seg_list+="  Segment $idx: ~${size_gib} GiB  (${start} MiB - ${end} MiB)\n"
        total_free=$(awk "BEGIN{print $total_free + $size_gib}")
        (( idx++ ))
    done <<< "$free_info"

    local warn=""
    if awk "BEGIN{exit ($total_free >= $MIN_RECOMMENDED_GIB)}"; then
        warn="\n WARNING: Total free space (~${total_free} GiB) is below the\n   recommended minimum of ${MIN_RECOMMENDED_GIB} GiB for this setup.\n   Installation may succeed but disk space will be tight.\n"
    fi

    ui_msgbox "Available Free Space on $disk" \
        "Unallocated segments found:\n\n${seg_list}${warn}\nThe largest usable segment will be used for the installation.\nExisting partitions (Windows, data, etc.) will NOT be touched."
}

# ---------------------------------------------------------------------------
# select_free_segment  →  sets FREE_SEG_START, FREE_SEG_END (MiB)
# ---------------------------------------------------------------------------
select_free_segment() {
    local disk="$1"
    local free_info
    free_info=$(detect_free_segments "$disk")

    # Pick the largest segment automatically
    local best_start="" best_end="" best_size=0
    while IFS='|' read -r start end size_mib; do
        if awk "BEGIN{exit !($size_mib > $best_size)}"; then
            best_start="$start"; best_end="$end"; best_size="$size_mib"
        fi
    done <<< "$free_info"

    FREE_SEG_START="$best_start"
    FREE_SEG_END="$best_end"
    log_info "Free segment selected: ${best_start} MiB – ${best_end} MiB (${best_size} MiB)"
}

# ---------------------------------------------------------------------------
# select_linux_partition  →  sets TARGET_LINUX_PART, saves to state
# ---------------------------------------------------------------------------
select_linux_partition() {
    local disk="$1"
    local parts
    parts=$(detect_linux_partitions "$disk")

    local menu_args=()
    while IFS='|' read -r dev size fstype label; do
        menu_args+=("$dev" "${fstype}  ${size}  label:${label}")
    done <<< "$parts"

    local choice
    choice=$(ui_menu "Select Target Partition" \
        "Choose the existing Linux partition to reinstall on.\n\n\
⚠  This partition will be COMPLETELY WIPED.\n\
   All data on it will be lost.\n\
   Other partitions will NOT be touched." \
        "${menu_args[@]}") || { clear; exit 0; }

    TARGET_LINUX_PART="$choice"
    set_state_str "root_partition" "$TARGET_LINUX_PART"
    log_info "Target Linux partition: $TARGET_LINUX_PART"
}

# ---------------------------------------------------------------------------
# confirm_destructive – require user to type disk/partition name before wiping
# ---------------------------------------------------------------------------
confirm_destructive() {
    local target="$1" label="${2:-disk}"
    local short_name
    short_name=$(basename "$target")

    ui_msgbox "⚠  FINAL WARNING" \
"You are about to DESTROY DATA on:\n\n\
  Device:  $target\n\n\
This action is IRREVERSIBLE.\n\n\
In the next dialog, type exactly:\n\n  $short_name\n\nto confirm, or cancel to abort."

    local entered
    entered=$(ui_inputbox "Confirm Destructive Operation" \
        "Type the $label name to confirm (exactly as shown):\n\n  $short_name" \
        ) || { clear; echo "Cancelled by user."; exit 0; }

    if [[ "$entered" != "$short_name" ]]; then
        ui_msgbox "Cancelled" "Name did not match. Installation aborted."
        exit 0
    fi
    log_info "Destructive operation confirmed for: $target"
}

# ---------------------------------------------------------------------------
# do_partition – partition the disk according to INSTALL_MODE and BOOT_MODE
# Sets EFI_PART and ROOT_PART when done.
# ---------------------------------------------------------------------------
do_partition() {
    local disk="$TARGET_DISK"

    case "$INSTALL_MODE" in
        wipe)      _partition_wipe      "$disk" ;;
        freespace) _partition_freespace "$disk" ;;
        reinstall) _partition_reinstall "$disk" ;;
        *) log_error "Unknown install mode: $INSTALL_MODE"; exit 1 ;;
    esac

    set_state_str "efi_partition"  "${EFI_PART:-}"
    set_state_str "root_partition" "$ROOT_PART"
    log_info "EFI_PART=$EFI_PART  ROOT_PART=$ROOT_PART"
}

# ── WIPE ────────────────────────────────────────────────────────────────────
_partition_wipe() {
    local disk="$1"
    log_step "Partitioning (wipe): $disk  [boot_mode=$BOOT_MODE]"

    # Wipe existing signatures
    run_cmd wipefs -a "$disk"

    if [[ "$BOOT_MODE" == "uefi" ]]; then
        run_cmd parted -s "$disk" mklabel gpt
        run_cmd parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
        run_cmd parted -s "$disk" set 1 esp on
        run_cmd parted -s "$disk" mkpart ROOT 513MiB 100%
        EFI_PART=$(part_dev "$disk" 1)
        ROOT_PART=$(part_dev "$disk" 2)
        NEW_ESP=true
    else
        # BIOS → MBR; no ESP needed; Limine goes to MBR
        run_cmd parted -s "$disk" mklabel msdos
        run_cmd parted -s "$disk" mkpart primary 1MiB 100%
        run_cmd parted -s "$disk" set 1 boot on
        EFI_PART=""
        ROOT_PART=$(part_dev "$disk" 1)
        NEW_ESP=false
    fi

    run_cmd partprobe "$disk"
    sleep 1
}

# ── FREE SPACE ──────────────────────────────────────────────────────────────
_partition_freespace() {
    local disk="$1"
    log_step "Partitioning (freespace): $disk  [boot_mode=$BOOT_MODE]"

    select_free_segment "$disk"
    local seg_start="$FREE_SEG_START" seg_end="$FREE_SEG_END"

    if [[ "$BOOT_MODE" == "uefi" ]]; then
        local esp
        esp=$(detect_existing_esp "$disk")

        if [[ -n "$esp" ]]; then
            log_info "Reusing existing ESP: $esp"
            EFI_PART="$esp"
            NEW_ESP=false
            run_cmd parted -s "$disk" mkpart ROOT "${seg_start}MiB" "${seg_end}MiB"
        else
            # Create ESP inside free segment (513 MiB) + rest for root
            local esp_end
            esp_end=$(awk "BEGIN{print $seg_start + 513}")
            run_cmd parted -s "$disk" mkpart ESP fat32 "${seg_start}MiB" "${esp_end}MiB"
            # Get the new partition number and set esp flag
            local new_part_num
            new_part_num=$(parted -m -s "$disk" print 2>/dev/null | awk -F: 'NR>2 {n=$1} END{print n}')
            run_cmd parted -s "$disk" set "${new_part_num}" esp on
            run_cmd parted -s "$disk" mkpart ROOT "${esp_end}MiB" "${seg_end}MiB"
            NEW_ESP=true
            # Identify new ESP by partition number
            EFI_PART=$(part_dev "$disk" "$new_part_num")
        fi

        # ROOT_PART = last partition on disk
        local last_num
        last_num=$(parted -m -s "$disk" print 2>/dev/null | awk -F: 'NR>2 {n=$1} END{print n}')
        ROOT_PART=$(part_dev "$disk" "$last_num")
    else
        # BIOS: just create partition in free space; Limine updates MBR
        run_cmd parted -s "$disk" mkpart primary "${seg_start}MiB" "${seg_end}MiB"
        EFI_PART=""
        NEW_ESP=false
        local last_num
        last_num=$(parted -m -s "$disk" print 2>/dev/null | awk -F: 'NR>2 {n=$1} END{print n}')
        ROOT_PART=$(part_dev "$disk" "$last_num")
    fi

    run_cmd partprobe "$disk"
    sleep 1
}

# ── REINSTALL ───────────────────────────────────────────────────────────────
_partition_reinstall() {
    local disk="$1"
    log_step "Partitioning (reinstall): $disk"

    select_linux_partition "$disk"
    ROOT_PART="$TARGET_LINUX_PART"

    if [[ "$BOOT_MODE" == "uefi" ]]; then
        local esp
        esp=$(detect_existing_esp "$disk")
        if [[ -z "$esp" ]]; then
            ui_msgbox "No ESP Found" \
"Reinstall mode requires an existing EFI System Partition (ESP).

None was found on $disk. This usually means the disk was set up
for BIOS/Legacy mode. Please choose 'Use entire disk' instead,
or switch to BIOS boot mode."
            exit 1
        fi
        EFI_PART="$esp"
        NEW_ESP=false
        log_info "Reusing ESP: $EFI_PART"
    else
        EFI_PART=""
        NEW_ESP=false
    fi
}
