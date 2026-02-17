#!/usr/bin/env bash

DIALOG_HEIGHT=20
DIALOG_WIDTH=70

require_tools() {
    if ! command -v dialog &> /dev/null; then
        echo "dialog not found. Install with: pacman -Sy dialog"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "jq not found. Install with: pacman -Sy jq"
        exit 1
    fi
}

menu() {
    dialog --clear \
        --menu "$1" \
        $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
        "${@:2}" \
        2>&1 >/dev/tty
}

confirm() {
    dialog --yesno "$1" 10 60
}
