#!/usr/bin/env bash
# modules/bluetooth.sh - Bluetooth stack installation and configuration
set -Eeuo pipefail

install_bluetooth() {
    log_info "Installing Bluetooth stack..."

    local pkgs=(
        bluez
        bluez-utils
        bluez-plugins
    )

    run_cmd_interactive pacman -S --noconfirm --needed "${pkgs[@]}"

    run_cmd systemctl enable bluetooth.service

    # Auto-power-on Bluetooth adapter
    local bt_conf="/etc/bluetooth/main.conf"
    if [[ -f "$bt_conf" ]]; then
        if grep -q "AutoEnable" "$bt_conf"; then
            sed -i 's/^#*AutoEnable.*/AutoEnable=true/' "$bt_conf"
        else
            echo -e "\n[Policy]\nAutoEnable=true" >> "$bt_conf"
        fi
    fi

    log_info "Bluetooth installed and enabled."
}
