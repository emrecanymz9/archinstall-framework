#!/usr/bin/env bash

ui_msg() {
    whiptail --msgbox "$1" 20 70
}

ui_confirm() {
    whiptail --yesno "$1" 12 60
}

ui_log() {
    echo "[LOG] $1"
}

ui_select_disk() {
    lsblk -dpno NAME,SIZE,TYPE | grep disk | \
    whiptail --menu "Select disk:" 20 70 10 \
    $(awk '{print $1, $2}') \
    3>&1 1>&2 2>&3
}

ui_select_disk_mode() {
    whiptail --menu "Select disk usage mode:" 15 60 5 \
    entire "Use entire disk" \
    existing "Use existing partition" \
    3>&1 1>&2 2>&3
}
