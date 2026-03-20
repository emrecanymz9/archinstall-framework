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
# Both UEFI and BIOS start unselected; user must make an explicit choice.
# The detected firmware mode is shown as a visual cue in the item description.
# ---------------------------------------------------------------------------
bootmode_screen() {
    local detected
    detected=$(detect_boot_mode)
    local detected_upper
    detected_upper=$(echo "$detected" | tr '[:lower:]' '[:upper:]')

    # Build item descriptions - add a "[*] Detected" marker to the matching mode
    local uefi_desc bios_desc
    if [[ "$detected" == "uefi" ]]; then
        uefi_desc="UEFI  (modern systems, GPT disk layout)  [* detected]"
        bios_desc="BIOS  (legacy systems, MBR disk layout)"
    else
        uefi_desc="UEFI  (modern systems, GPT disk layout)"
        bios_desc="BIOS  (legacy systems, MBR disk layout)  [* detected]"
    fi

    local choice=""
    # Loop until the user explicitly selects a mode (radiolist returns empty
    # string when OK is pressed without selecting any item).
    while [[ -z "$choice" ]]; do
        choice=$(_dlg \
            --title "Boot Mode Selection" \
            --radiolist \
"System firmware: ${detected_upper}

Select the boot mode that matches your firmware.
Use arrow keys to highlight, Space to select, then Enter to confirm.
Both UEFI and BIOS are available - you must choose one." \
            20 72 4 \
            "uefi" "$uefi_desc" "off" \
            "bios" "$bios_desc" "off" \
        ) || { clear; exit 0; }

        if [[ -z "$choice" ]]; then
            _dlg --title "No Selection" --msgbox \
"Please select a boot mode before continuing.

Use the Space bar to select UEFI or BIOS,
then press Enter to confirm." \
                10 58
        fi
    done

    # Show mode-specific firmware instructions
    case "$choice" in
        uefi)
            _dlg --title "UEFI Mode - Firmware Checklist" --msgbox \
"Before continuing, verify in your firmware (UEFI) settings:

  Boot mode:    UEFI  (not Legacy/CSM)
  Secure Boot:  DISABLED  (re-enable after install via sbctl)
  CSM/Legacy:   DISABLED
  Boot device:  USB drive with this ISO

If any setting needs changing, press Cancel on the next screen,
adjust your firmware, then reboot and re-run the installer." \
                16 68
            ;;
        bios)
            _dlg --title "BIOS Mode - Firmware Checklist" --msgbox \
"Before continuing, verify in your firmware (BIOS) settings:

  Boot mode:    Legacy / CSM  (not UEFI)
  Boot device:  USB drive with this ISO
  Secure Boot:  Not applicable in BIOS mode

Note: BIOS mode uses MBR disk layout.
If you need UEFI, cancel, adjust firmware settings, and reboot." \
                14 68
            ;;
    esac

    # Final decision: continue or exit
    local choice_upper
    choice_upper=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
    if ! _dlg --title "Ready to Continue?" --yesno \
"Proceed with installation in ${choice_upper} mode?

Select No to exit and adjust your firmware settings." \
            10 58; then
        clear
        echo "Exiting installer. Adjust your firmware settings and reboot."
        exit 0
    fi

    BOOT_MODE="$choice"
    set_state_str "boot_mode" "$BOOT_MODE"
    log_info "Boot mode selected: $BOOT_MODE"
}
