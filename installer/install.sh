#!/usr/bin/env bash
# installer/install.sh - Phase 1 orchestrator (ISO environment)
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Resolve framework root and export for all sub-scripts
# ---------------------------------------------------------------------------
FRAMEWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FRAMEWORK_ROOT
export MOUNT_POINT="/mnt"
export LOG_FILE="/tmp/archinstall.log"
export UI_BACKTITLE="ArchInstall Framework - Installer"

# ---------------------------------------------------------------------------
# Source modules (defines functions; does not execute them)
# ---------------------------------------------------------------------------
source "$FRAMEWORK_ROOT/installer/ui.sh"
source "$FRAMEWORK_ROOT/installer/state.sh"
source "$FRAMEWORK_ROOT/installer/executor.sh"
source "$FRAMEWORK_ROOT/installer/bootmode.sh"
source "$FRAMEWORK_ROOT/installer/disk.sh"
source "$FRAMEWORK_ROOT/installer/luks.sh"
source "$FRAMEWORK_ROOT/installer/filesystem.sh"
source "$FRAMEWORK_ROOT/installer/limine.sh"
source "$FRAMEWORK_ROOT/installer/microcode.sh"

# ===========================================================================
# LOCAL HELPER FUNCTIONS
# All helpers defined before main() so they are available when called.
# ===========================================================================

_collect_identity() {
    # -- Hostname --
    while true; do
        HOSTNAME=$(ui_inputbox "Computer Name (Hostname)" \
"Choose a name for this computer.

The hostname appears in terminal prompts and on the network.
  Example prompt:  username@my-arch-pc:\$

Rules: lowercase letters, numbers, hyphens. No spaces.
  Examples: my-arch-pc  arch-desktop  johns-laptop" \
            "my-arch-pc") || { clear; exit 0; }
        if [[ "$HOSTNAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
            break
        fi
        ui_msgbox "Invalid Hostname" \
            "Hostname must start with a letter or digit,
contain only lowercase letters, digits, hyphens,
and be 1-63 characters long."
    done
    set_state_str "hostname" "$HOSTNAME"

    # -- Username --
    while true; do
        USERNAME=$(ui_inputbox "Username (Login Name)" \
"Choose your Linux login username.

This is the name you log in with. It appears in the terminal:
  Example prompt:  user@${HOSTNAME}:\$

Rules: lowercase letters, numbers, underscores, hyphens.
  Examples: john  arch_user  jane-doe" \
            "") || { clear; exit 0; }
        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [[ "$USERNAME" != "root" ]]; then
            break
        fi
        ui_msgbox "Invalid Username" \
            "Username must start with a lowercase letter or underscore,
contain only lowercase letters, digits, underscores, hyphens,
be 1-32 characters, and not be 'root'."
    done
    set_state_str "username" "$USERNAME"

    # -- User password --
    while true; do
        USER_PASS=$(ui_passwordbox "User Password" \
            "Enter password for user '$USERNAME':") || { clear; exit 0; }
        local confirm
        confirm=$(ui_passwordbox "User Password - Confirm" \
            "Re-enter the password for '$USERNAME':") || { clear; exit 0; }
        if [[ "$USER_PASS" == "$confirm" ]]; then
            break
        fi
        ui_msgbox "Password Mismatch" "Passwords do not match. Please try again."
    done

    # -- Root password / lock --
    local root_choice
    root_choice=$(ui_radiolist "Root Account" \
"Configure the root (administrator) account.

Disable direct root login (recommended):
  - Root login via terminal is disabled
  - You can still use 'sudo' for admin tasks

Set root password:
  - Root login is enabled
  - Useful for recovery / server setups" \
        "locked"   "Disable direct root login (recommended)" "on" \
        "password" "Set a root password"                     "off" \
    ) || { clear; exit 0; }

    if [[ "$root_choice" == "password" ]]; then
        while true; do
            ROOT_PASS=$(ui_passwordbox "Root Password" \
                "Enter root password:") || { clear; exit 0; }
            local rconfirm
            rconfirm=$(ui_passwordbox "Root Password - Confirm" \
                "Re-enter root password:") || { clear; exit 0; }
            if [[ "$ROOT_PASS" == "$rconfirm" ]]; then
                break
            fi
            ui_msgbox "Password Mismatch" "Passwords do not match. Please try again."
        done
        ROOT_LOCKED=false
    else
        ROOT_PASS=""
        ROOT_LOCKED=true
    fi
    if [[ "$ROOT_LOCKED" == "true" ]]; then
        set_state "root_locked" "true"
    else
        set_state "root_locked" "false"
    fi
}

_show_summary() {
    local enc_label="No"
    [[ "${ENCRYPTION:-false}" == "true" ]] && enc_label="Yes (LUKS2)"

    local root_label="Password-protected"
    [[ "${ROOT_LOCKED:-true}" == "true" ]] && root_label="Direct login disabled (sudo only)"

    if ! ui_yesno "Installation Summary" \
"Please review your choices before proceeding:

  Boot mode:    $BOOT_MODE
  Target disk:  $TARGET_DISK
  Install mode: $INSTALL_MODE
  Encryption:   $enc_label
  Filesystem:   $FILESYSTEM
  Bootloader:   $BOOTLOADER
  Hostname:     $HOSTNAME
  Username:     $USERNAME
  Root account: $root_label

Proceed with installation?"; then
        clear
        exit 0
    fi
}

_install_base() {
    local pkgs=(
        base base-devel
        linux-zen linux-zen-headers linux-firmware
        btrfs-progs e2fsprogs dosfstools
        cryptsetup lvm2
        networkmanager network-manager-applet
        sudo git vim nano
        efibootmgr
        zram-generator
        jq
        bash-completion
        man-db man-pages
    )

    log_info "Running pacstrap..."
    if ! pacstrap -K "$MOUNT_POINT" "${pkgs[@]}" >> "$LOG_FILE" 2>&1; then
        log_error "pacstrap failed. Check $LOG_FILE"
        exit 1
    fi

    # Copy framework to installed system for Phase 2
    mkdir -p "$MOUNT_POINT/opt/archinstall"
    cp -r "$FRAMEWORK_ROOT/installer"   "$MOUNT_POINT/opt/archinstall/"
    cp -r "$FRAMEWORK_ROOT/postinstall" "$MOUNT_POINT/opt/archinstall/"
    cp -r "$FRAMEWORK_ROOT/modules"     "$MOUNT_POINT/opt/archinstall/"
    cp -r "$FRAMEWORK_ROOT/config"      "$MOUNT_POINT/opt/archinstall/"

    log_info "Base system installed."
}

_configure_initramfs() {
    local mp="$MOUNT_POINT"
    local hooks="base udev autodetect microcode modconf keyboard keymap consolefont block"

    if [[ "${ENCRYPTION:-false}" == "true" ]]; then
        hooks+=" encrypt"
    fi

    if [[ "${FILESYSTEM:-btrfs}" == "btrfs" ]]; then
        hooks+=" btrfs filesystems fsck"
    else
        hooks+=" filesystems fsck"
    fi

    cat > "$mp/etc/mkinitcpio.conf" <<EOF
MODULES=()
BINARIES=()
FILES=()
HOOKS=(${hooks})
EOF

    chroot_run "mkinitcpio -P"
    log_info "initramfs regenerated."
}

_configure_system() {
    local mp="$MOUNT_POINT"

    # Timezone
    local timezone
    timezone=$(ui_inputbox "Timezone" \
        "Enter your timezone (e.g. Europe/Istanbul, America/New_York, Asia/Tokyo):" \
        "UTC") || timezone="UTC"
    chroot_run "ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime"
    chroot_run "hwclock --systohc"
    log_info "Timezone: $timezone"

    # Locale
    echo "en_US.UTF-8 UTF-8" >> "$mp/etc/locale.gen"
    echo "LANG=en_US.UTF-8"  >  "$mp/etc/locale.conf"
    chroot_run "locale-gen"

    # Hostname
    echo "$HOSTNAME" > "$mp/etc/hostname"
    cat > "$mp/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain  ${HOSTNAME}
EOF

    # mkinitcpio hooks
    _configure_initramfs

    # Users
    chroot_run "useradd -m -G wheel,audio,video,storage,optical -s /bin/bash $USERNAME"
    printf '%s:%s\n' "$USERNAME" "$USER_PASS" | chroot_run "chpasswd"
    log_info "User '$USERNAME' created."

    # Root account
    if [[ "${ROOT_LOCKED:-true}" == "true" ]]; then
        chroot_run "passwd -l root"
        log_info "Root account locked."
    else
        printf '%s:%s\n' "root" "$ROOT_PASS" | chroot_run "chpasswd"
        log_info "Root password set."
    fi

    # Sudo: wheel group with password
    cat > "$mp/etc/sudoers.d/10-wheel" <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
    chmod 440 "$mp/etc/sudoers.d/10-wheel"

    # Enable services
    chroot_run "systemctl enable NetworkManager"
    chroot_run "systemctl enable systemd-resolved"
    log_info "Services enabled."
}

_install_phase2_service() {
    local mp="$MOUNT_POINT"

    cat > "$mp/etc/systemd/system/archinstall-phase2.service" <<'EOF'
[Unit]
Description=ArchInstall Framework - Phase 2 (Post Install)
Documentation=file:///opt/archinstall/README.md
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/archinstall/phase2-done

[Service]
Type=oneshot
ExecStart=/opt/archinstall/postinstall/install.sh
ExecStartPost=/bin/bash -c 'mkdir -p /var/lib/archinstall && touch /var/lib/archinstall/phase2-done'
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=3600

[Install]
WantedBy=multi-user.target
EOF

    chroot_run "systemctl enable archinstall-phase2.service"
    log_info "Phase 2 first-boot service installed and enabled."
}

# ===========================================================================
# MAIN - executes after all functions are defined
# ===========================================================================
main() {
    # Must run as root
    if [[ "$EUID" -ne 0 ]]; then
        echo "ERROR: Run this installer as root (or with sudo)."
        exit 1
    fi

    require_tools
    init_state
    log_info "ArchInstall Framework starting. Log: $LOG_FILE"

    # Clear the screen so dialog appears immediately on the next call.
    # Without this, on VM/TTY consoles (e.g. VMware Workstation) ncurses can
    # wait for a keypress before rendering its first window.
    clear

    log_step "Step 1: Boot mode selection"
    bootmode_screen

    log_step "Step 2: Disk selection"
    select_disk

    log_step "Step 3: Install mode"
    choose_install_mode "$TARGET_DISK"

    log_step "Step 4: Destructive confirmation"
    case "$INSTALL_MODE" in
        wipe)      confirm_destructive "$TARGET_DISK"                        "disk" ;;
        freespace) confirm_destructive "$TARGET_DISK"                        "disk" ;;
        reinstall) confirm_destructive "${TARGET_LINUX_PART:-$TARGET_DISK}" "partition" ;;
    esac

    log_step "Step 5: Encryption"
    ask_encryption

    log_step "Step 6: Filesystem"
    ask_filesystem

    log_step "Step 7: Bootloader"
    ask_bootloader

    log_step "Step 8: Identity"
    _collect_identity

    log_step "Step 9: Pre-install summary"
    _show_summary

    log_step "Step 10: Partitioning"
    do_partition

    log_step "Step 11: LUKS setup"
    if [[ "${ENCRYPTION:-false}" == "true" ]]; then
        setup_luks
    else
        setup_noencrypt
    fi

    log_step "Step 12: Format filesystems"
    format_root
    format_efi

    log_step "Step 13: Mount filesystems"
    mount_filesystems

    log_step "Step 14: pacstrap base system"
    _install_base

    log_step "Step 15: fstab"
    genfstab -U "$MOUNT_POINT" >> "$MOUNT_POINT/etc/fstab"
    log_info "fstab written."

    log_step "Step 16: Chroot configuration"
    _configure_system

    log_step "Step 17: Microcode"
    install_microcode

    log_step "Step 18: Bootloader"
    install_bootloader

    log_step "Step 19: Phase 2 service"
    _install_phase2_service

    mark_done "phase1_done"

    ui_msgbox "Installation Complete!" \
"Phase 1 (Installer) is complete!

The system is ready to boot into Arch Linux.

On first boot:
  - Post Install (Phase 2) will run automatically
  - You can also run it manually:
    sudo /opt/archinstall/postinstall/install.sh

Log file: $LOG_FILE

Please remove the USB drive and reboot."

    clear
    log_info "Phase 1 complete. Ready to reboot."
}

main "$@"
