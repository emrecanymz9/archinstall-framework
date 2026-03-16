#!/usr/bin/env bash
# installer/bootmode.sh - boot mode detection and selection dialog
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# detect_boot_mode  ->  stdout: "uefi" | "bios"
# ---------------------------------------------------------------------------
detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

# ---------------------------------------------------------------------------
# bootmode_screen - present radiolist, show instructions, allow exit
# Sets global BOOT_MODE and saves to state.
# ---------------------------------------------------------------------------
bootmode_screen() {
    # Clear the terminal before launching the first dialog widget.
    # Without this, any log/banner text printed before this function is called
    # remains on screen and the dialog TUI appears to "wait" for user input
    # before rendering on some Linux console (TTY) configurations.
    clear

    local detected
    detected=$(detect_boot_mode)

    # Pre-select detected mode, but let user override
    local uefi_sel="off" bios_sel="off"
    [[ "$detected" == "uefi" ]] && uefi_sel="on" || bios_sel="on"

    local choice
    choice=$(ui_radiolist \
        "Boot Mode" \
        "Detected: $(echo "$detected" | tr '[:lower:]' '[:upper:]')\n\nSelect the boot mode your system uses.\nIf unsure, keep the auto-detected option." \
        "uefi" "UEFI  (modern systems, GPT disk layout)"        "$uefi_sel" \
        "bios" "BIOS  (legacy systems, MBR disk layout)"        "$bios_sel" \
    ) || { clear; exit 0; }

    # Show mode-specific firmware instructions
    case "$choice" in
        uefi)
            ui_msgbox "UEFI Mode - Firmware Checklist" \
"Before continuing, verify in your firmware (UEFI) settings:\n
  - Boot mode:     UEFI  (not Legacy/CSM)\n
  - Secure Boot:   DISABLED  (re-enable after install via sbctl)\n
  - CSM/Legacy:    DISABLED\n
  - Boot device:   USB drive with this ISO\n
\nIf any of the above needs changing, choose Exit below,\nadjust firmware settings, then reboot and re-run the installer."
            ;;
        bios)
            ui_msgbox "BIOS Mode - Firmware Checklist" \
"Before continuing, verify in your firmware (BIOS) settings:\n
  - Boot mode:     Legacy / CSM  (not UEFI)\n
  - Boot device:   USB drive with this ISO\n
  - Secure Boot:   Not applicable in BIOS mode\n
\nNote: BIOS mode uses MBR disk layout.\nIf you need UEFI, choose Exit, adjust settings, and reboot."
            ;;
    esac

    # Final decision: continue or exit
    if ! ui_yesno "Ready to Continue?" \
            "Do you want to proceed with the installation in $choice mode?\n\nSelect 'No' to exit and adjust your firmware settings."; then
        clear
        echo "Exiting installer. Adjust your firmware settings and reboot."
        exit 0
    fi

    BOOT_MODE="$choice"
    set_state_str "boot_mode" "$BOOT_MODE"
    log_info "Boot mode selected: $BOOT_MODE"
}
