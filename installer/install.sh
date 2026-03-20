#!/usr/bin/env bash

set -e

# === GLOBAL STATE ===
STATE_FILE="/tmp/archinstall_state"

# === INIT ===
init() {
    clear
    echo "ArchInstall Framework starting..."
    sleep 1
}

# === CLEANUP ===
cleanup() {
    clear
}
trap cleanup EXIT

# === UI WRAPPER ===
menu() {
    local title="$1"
    local prompt="$2"
    shift 2

    dialog --clear \
        --backtitle "ArchInstall Framework" \
        --title "$title" \
        --menu "$prompt" 15 60 6 \
        "$@" \
        3>&1 1>&2 2>&3
}

# === MAIN MENU ===
main_menu() {
    while true; do
        choice=$(menu "Main Menu" "Select an option:" \
            1 "Disk Setup" \
            2 "Bootloader" \
            3 "Install System" \
            4 "Post Install" \
            5 "Exit")

        exit_status=$?

        # Backspace / ESC
        if [ $exit_status -ne 0 ]; then
            break
        fi

        case $choice in
            1) disk_menu ;;
            2) boot_menu ;;
            3) install_system ;;
            4) post_install ;;
            5) break ;;
        esac
    done
}

# === DISK MENU ===
disk_menu() {
    disks=$(lsblk -d -o NAME,SIZE,MODEL | tail -n +2)

    options=()
    while read -r line; do
        name=$(echo $line | awk '{print $1}')
        size=$(echo $line | awk '{print $2}')
        model=$(echo $line | cut -d ' ' -f3-)
        options+=("$name" "$size $model")
    done <<< "$disks"

    choice=$(dialog --menu "Select Disk:" 15 60 5 "${options[@]}" 3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
        echo "DISK=$choice" > "$STATE_FILE"
    fi
}

# === BOOT MENU ===
boot_menu() {
    choice=$(dialog --menu "Select Bootloader:" 15 60 5 \
        "systemd-boot" "UEFI recommended" \
        "grub" "Legacy/BIOS" \
        3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
        echo "BOOT=$choice" >> "$STATE_FILE"
    fi
}

# === INSTALL ===
install_system() {
    dialog --msgbox "Installing base system..." 6 40

    # Placeholder
    sleep 2
}

# === POST INSTALL ===
post_install() {
    dialog --msgbox "Post-install setup..." 6 40
}

# === ENTRY ===
init
main_menu