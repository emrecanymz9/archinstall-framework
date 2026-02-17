#!/usr/bin/env bash

detect_boot_mode() {
    if [ -d /sys/firmware/efi ]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

bootmode_screen() {
    MODE=$(detect_boot_mode)

    if [ "$MODE" = "bios" ]; then
        dialog --msgbox "System booted in BIOS mode.\n\nUEFI is strongly recommended.\nIf Windows is installed in UEFI mode DO NOT continue.\n\nReboot and enable UEFI." 12 60
        exit 1
    fi

    set_state boot_mode "\"uefi\""
}
