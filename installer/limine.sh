#!/usr/bin/env bash
# installer/limine.sh - bootloader selection and installation (Limine + systemd-boot/UKI)
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# ask_bootloader  ->  sets BOOTLOADER ("limine"|"systemd-boot"), saves to state
# Note: systemd-boot/UKI only available on UEFI
# ---------------------------------------------------------------------------
ask_bootloader() {
    if [[ "$BOOT_MODE" == "bios" ]]; then
        BOOTLOADER="limine"
        set_state_str "bootloader" "limine"
        log_info "BIOS mode: bootloader forced to Limine"
        return
    fi

    local choice
    choice=$(ui_radiolist "Bootloader" \
        "Choose a bootloader for your Arch Linux installation.\n\n\
Limine: fast, minimal, supports both UEFI and BIOS.\n\n\
systemd-boot + UKI: generates a Unified Kernel Image containing\n\
  kernel + initrd + cmdline in a single signed EFI binary.\n\
  Simpler Secure Boot signing. Requires UEFI." \
        "limine"        "Limine         (fast, minimal, recommended)" "on" \
        "systemd-boot"  "systemd-boot + UKI  (unified kernel image)"  "off" \
    ) || { clear; exit 0; }

    BOOTLOADER="$choice"
    set_state_str "bootloader" "$BOOTLOADER"
    log_info "Bootloader: $BOOTLOADER"
}

# ---------------------------------------------------------------------------
# install_bootloader  ->  dispatches to the correct backend
# ---------------------------------------------------------------------------
install_bootloader() {
    case "$BOOTLOADER" in
        limine)       _install_limine       ;;
        systemd-boot) _install_systemd_boot ;;
        *) log_error "Unknown bootloader: $BOOTLOADER"; exit 1 ;;
    esac
}

# ===========================================================================
# LIMINE
# ===========================================================================
_install_limine() {
    local mp="${MOUNT_POINT:-/mnt}"
    log_step "Installing Limine bootloader  [boot_mode=$BOOT_MODE]"

    chroot_run "pacman -S --noconfirm --needed limine efibootmgr"

    local root_uuid
    root_uuid=$(blkid -s UUID -o value "$ROOT_MAPPED")

    local luks_cmdline=""
    if [[ "${ENCRYPTION:-false}" == "true" ]]; then
        luks_cmdline="rd.luks.name=${LUKS_UUID}=cryptroot "
    fi

    local fs_opts="rootflags=subvol=/@"
    [[ "$FILESYSTEM" == "ext4" ]] && fs_opts=""

    local cmdline="${luks_cmdline}root=UUID=${root_uuid} rw ${fs_opts} quiet splash"
    local microcode_entry=""
    if [[ -n "${MICROCODE:-}" ]]; then
        microcode_entry="    MODULE_PATH=/boot/${MICROCODE}.img\n"
    fi

    if [[ "$BOOT_MODE" == "uefi" ]]; then
        _install_limine_uefi "$mp" "$cmdline" "$microcode_entry"
    else
        _install_limine_bios "$mp" "$cmdline" "$microcode_entry"
    fi
}

_install_limine_uefi() {
    local mp="$1" cmdline="$2" microcode_entry="$3"

    mkdir -p "$mp/boot/EFI/BOOT"
    mkdir -p "$mp/boot/limine"

    # Copy Limine EFI binary
    cp "$mp/usr/share/limine/BOOTX64.EFI" "$mp/boot/EFI/BOOT/BOOTX64.EFI"
    cp "$mp/usr/share/limine/limine-bios.sys" "$mp/boot/limine/" 2>/dev/null || true

    # Write limine.conf
    cat > "$mp/boot/limine/limine.conf" <<EOF
timeout: 5
default_entry: 1

/Arch Linux
    protocol: linux
    kernel_path: boot:///boot/vmlinuz-linux-zen
${microcode_entry}    module_path: boot:///boot/initramfs-linux-zen.img
    cmdline: ${cmdline}

/Arch Linux (fallback)
    protocol: linux
    kernel_path: boot:///boot/vmlinuz-linux-zen
${microcode_entry}    module_path: boot:///boot/initramfs-linux-zen-fallback.img
    cmdline: ${cmdline}
EOF

    # Register with EFI using reliable kernel sysfs attributes
    local disk_dev part_num
    disk_dev=$(lsblk -ndo PKNAME "$EFI_PART" 2>/dev/null) || true
    if [[ -z "$disk_dev" ]]; then
        # Fallback: strip partition suffix from device path
        if [[ "$EFI_PART" =~ (nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
            disk_dev="${BASH_REMATCH[1]}"
        elif [[ "$EFI_PART" =~ (mmcblk[0-9]+)p[0-9]+$ ]]; then
            disk_dev="${BASH_REMATCH[1]}"
        else
            disk_dev="${EFI_PART%[0-9]}"
            disk_dev="${disk_dev##*/}"
        fi
    fi
    part_num=$(cat /sys/class/block/"$(basename "$EFI_PART")"/partition 2>/dev/null || echo 1)

    chroot_run "efibootmgr --create \
        --disk /dev/${disk_dev} \
        --part ${part_num} \
        --label 'Arch Linux (Limine)' \
        --loader '\\EFI\\BOOT\\BOOTX64.EFI' \
        --unicode '' || true"

    log_info "Limine UEFI installed."
}

_install_limine_bios() {
    local mp="$1" cmdline="$2" microcode_entry="$3"

    mkdir -p "$mp/boot/limine"

    cp "$mp/usr/share/limine/limine-bios.sys" "$mp/boot/limine/"

    cat > "$mp/boot/limine/limine.conf" <<EOF
timeout: 5
default_entry: 1

/Arch Linux
    protocol: linux
    kernel_path: boot:///boot/vmlinuz-linux-zen
${microcode_entry}    module_path: boot:///boot/initramfs-linux-zen.img
    cmdline: ${cmdline}

/Arch Linux (fallback)
    protocol: linux
    kernel_path: boot:///boot/vmlinuz-linux-zen
${microcode_entry}    module_path: boot:///boot/initramfs-linux-zen-fallback.img
    cmdline: ${cmdline}
EOF

    # Deploy to MBR - use TARGET_DISK directly (most reliable for BIOS)
    local disk_base
    disk_base=$(basename "$TARGET_DISK")
    chroot_run "limine bios-install /dev/${disk_base}"

    log_info "Limine BIOS installed to MBR of /dev/${disk_base}."
}

# ===========================================================================
# SYSTEMD-BOOT + UKI
# ===========================================================================
_install_systemd_boot() {
    local mp="${MOUNT_POINT:-/mnt}"
    log_step "Installing systemd-boot + UKI"

    chroot_run "pacman -S --noconfirm --needed systemd efibootmgr"

    # Install bootloader to ESP
    chroot_run "bootctl install --esp-path=/boot"

    # Build kernel command line
    local root_uuid
    root_uuid=$(blkid -s UUID -o value "$ROOT_MAPPED")

    local luks_cmdline=""
    if [[ "${ENCRYPTION:-false}" == "true" ]]; then
        luks_cmdline="rd.luks.name=${LUKS_UUID}=cryptroot "
    fi

    local fs_opts="rootflags=subvol=/@"
    [[ "$FILESYSTEM" == "ext4" ]] && fs_opts=""

    # Write kernel cmdline for UKI
    local cmdline_file="$mp/etc/kernel/cmdline"
    mkdir -p "$(dirname "$cmdline_file")"
    echo "${luks_cmdline}root=UUID=${root_uuid} rw ${fs_opts} quiet splash" \
        > "$cmdline_file"

    # Configure mkinitcpio preset for UKI generation
    local preset_dir="$mp/etc/mkinitcpio.d"
    mkdir -p "$preset_dir"
    cat > "$preset_dir/linux-zen.preset" <<'EOF'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux-zen"

PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux-zen.efi"
default_options=""

fallback_uki="/boot/EFI/Linux/arch-linux-zen-fallback.efi"
fallback_options="-S autodetect"
EOF

    mkdir -p "$mp/boot/EFI/Linux"

    # Regenerate initramfs / UKI
    chroot_run "mkinitcpio -p linux-zen"

    log_info "systemd-boot + UKI installed."
}
