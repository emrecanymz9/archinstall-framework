#!/usr/bin/env bash
# modules/secureboot.sh – Secure Boot via sbctl (Phase 2, post-reboot)
set -Eeuo pipefail

setup_secureboot() {
    log_info "Checking Secure Boot status..."

    # Check if sbctl is already set up
    if sbctl status 2>/dev/null | grep -q "Setup Mode.*Enabled"; then
        _do_secureboot_enroll
    else
        _show_secureboot_instructions
    fi
}

_do_secureboot_enroll() {
    log_info "System is in Setup Mode – proceeding with sbctl enrollment."

    run_cmd_interactive pacman -S --noconfirm --needed sbctl

    # Create keys
    run_cmd sbctl create-keys

    # Enroll keys (with Microsoft UEFI CA for hardware compatibility)
    run_cmd sbctl enroll-keys --microsoft

    # Sign the bootloader and kernel
    _sign_efi_binaries

    ui_msgbox "Secure Boot Keys Enrolled" \
"Secure Boot keys have been created and enrolled.\n\n\
EFI binaries have been signed.\n\n\
NEXT STEPS:\n\
  1. Reboot your system\n\
  2. Enter firmware settings (UEFI setup)\n\
  3. Enable Secure Boot\n\
  4. Boot into Arch Linux\n\
  5. Verify: sbctl status"
}

_sign_efi_binaries() {
    log_info "Signing EFI binaries with sbctl..."

    # Sign all previously registered files
    sbctl sign-all 2>/dev/null || true

    # Register and sign common paths; nullglob prevents errors on missing globs
    local -a efi_paths=(
        /boot/EFI/BOOT/BOOTX64.EFI
        /boot/vmlinuz-linux-zen
        /boot/limine/limine.efi
        /usr/lib/systemd/boot/efi/systemd-bootx64.efi
    )

    # Handle glob paths separately with nullglob
    local oldopt; oldopt=$(shopt -p nullglob)
    shopt -s nullglob
    local glob_matches=(/boot/EFI/Linux/*.efi)
    eval "$oldopt"

    efi_paths+=("${glob_matches[@]}")

    for f in "${efi_paths[@]}"; do
        [[ -f "$f" ]] || continue
        sbctl sign -s "$f" 2>/dev/null && log_info "Signed: $f" || log_warn "Could not sign: $f"
    done

    log_info "EFI binaries signed."
}

_show_secureboot_instructions() {
    local sb_status
    sb_status=$(sbctl status 2>/dev/null || echo "sbctl not installed")

    ui_msgbox "Secure Boot Setup" \
"Secure Boot status: $sb_status\n\n\
To set up Secure Boot:\n\
\n\
  Step 1 – Enter firmware (UEFI) settings\n\
    • Clear/delete existing Secure Boot keys\n\
    • Enable 'Setup Mode' or 'Custom Mode'\n\
    • This allows enrolling your own keys\n\
\n\
  Step 2 – Reboot into Arch Linux\n\
    • Run this script again: /opt/archinstall/modules/secureboot.sh\n\
    • Or run: sbctl create-keys && sbctl enroll-keys --microsoft\n\
\n\
  Step 3 – Sign EFI binaries\n\
    • sbctl sign-all\n\
\n\
  Step 4 – Enable Secure Boot in firmware\n\
    • Reboot into firmware settings\n\
    • Enable Secure Boot\n\
    • Boot Arch Linux\n\
\n\
NOTE: Hardware varies. Some systems require vendor-specific steps.\n\
      The --microsoft flag adds Microsoft CA for hardware compatibility\n\
      (required for most NVIDIA/USB controllers)."

    # Still install sbctl for manual use
    run_cmd_interactive pacman -S --noconfirm --needed sbctl
    log_info "sbctl installed. Manual Secure Boot setup required."
}