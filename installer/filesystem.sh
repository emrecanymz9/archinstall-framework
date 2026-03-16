#!/usr/bin/env bash
# installer/filesystem.sh - filesystem selection, formatting, and mounting
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# ask_filesystem  ->  sets FILESYSTEM ("btrfs"|"ext4"), saves to state
# ---------------------------------------------------------------------------
ask_filesystem() {
    local choice
    choice=$(ui_radiolist "Filesystem" \
        "Choose the filesystem for the root (and home) partition.\n\n\
btrfs: modern, supports snapshots, compression (zstd), subvolumes.\n\
  Subvolumes created: @ (root)  @home  @snapshots\n\
  Compression: zstd level 5 (good balance of speed and ratio)\n\n\
ext4: simple, reliable, widely supported, no built-in snapshots." \
        "btrfs" "btrfs  (snapshots + compression, recommended)" "on" \
        "ext4"  "ext4   (classic, simple)"                      "off" \
    ) || { clear; exit 0; }

    FILESYSTEM="$choice"
    set_state_str "filesystem" "$FILESYSTEM"
    log_info "Filesystem: $FILESYSTEM"
}

# ---------------------------------------------------------------------------
# format_root  ->  formats ROOT_MAPPED with chosen filesystem
# ---------------------------------------------------------------------------
format_root() {
    log_step "Formatting root: $ROOT_MAPPED  [$FILESYSTEM]"
    case "$FILESYSTEM" in
        btrfs) run_cmd mkfs.btrfs -f -L "ARCH_ROOT" "$ROOT_MAPPED" ;;
        ext4)  run_cmd mkfs.ext4  -F -L "ARCH_ROOT" "$ROOT_MAPPED" ;;
        *) log_error "Unknown filesystem: $FILESYSTEM"; exit 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# format_efi  ->  formats EFI_PART as FAT32 (skip if reusing existing ESP)
# NEW_ESP is exported by disk.sh partitioning helpers when a new ESP is
# created; it is empty when an existing ESP is reused.
# ---------------------------------------------------------------------------
format_efi() {
    [[ -z "${EFI_PART:-}" ]] && return 0
    if [[ "${NEW_ESP:-false}" == "true" ]]; then
        log_info "Formatting new ESP: $EFI_PART"
        run_cmd mkfs.fat -F32 -n "EFI" "$EFI_PART"
    else
        log_info "Reusing existing ESP: $EFI_PART (not reformatted)"
    fi
}

# ---------------------------------------------------------------------------
# mount_filesystems  ->  mount root (+ subvols) and ESP
# ---------------------------------------------------------------------------
mount_filesystems() {
    local mp="${MOUNT_POINT:-/mnt}"
    log_step "Mounting filesystems at $mp"

    case "$FILESYSTEM" in
        btrfs) _mount_btrfs "$mp" ;;
        ext4)  _mount_ext4  "$mp" ;;
    esac

    # Mount ESP
    if [[ -n "${EFI_PART:-}" ]]; then
        mkdir -p "$mp/boot"
        run_cmd mount "$EFI_PART" "$mp/boot"
        log_info "Mounted ESP at $mp/boot"
    fi
}

_mount_btrfs() {
    local mp="$1"
    local opts="rw,noatime,compress=zstd:5,space_cache=v2"

    # Temporary mount to create subvolumes
    run_cmd mount -o "$opts" "$ROOT_MAPPED" "$mp"

    run_cmd btrfs subvolume create "$mp/@"
    run_cmd btrfs subvolume create "$mp/@home"
    run_cmd btrfs subvolume create "$mp/@snapshots"

    run_cmd umount "$mp"

    # Remount with subvolumes
    run_cmd mount -o "${opts},subvol=@"          "$ROOT_MAPPED" "$mp"
    mkdir -p "$mp"/{home,.snapshots}
    run_cmd mount -o "${opts},subvol=@home"      "$ROOT_MAPPED" "$mp/home"
    run_cmd mount -o "${opts},subvol=@snapshots" "$ROOT_MAPPED" "$mp/.snapshots"

    log_info "btrfs subvolumes mounted: @  @home  @snapshots"
}

_mount_ext4() {
    local mp="$1"
    run_cmd mount "$ROOT_MAPPED" "$mp"
    mkdir -p "$mp/home"
    log_info "ext4 root mounted at $mp"
}

# ---------------------------------------------------------------------------
# unmount_filesystems  ->  unmount in reverse order
# ---------------------------------------------------------------------------
unmount_filesystems() {
    local mp="${MOUNT_POINT:-/mnt}"
    log_info "Unmounting $mp..."
    run_cmd umount -R "$mp" 2>/dev/null || true
}