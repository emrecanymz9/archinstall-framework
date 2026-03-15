#!/usr/bin/env bash
# modules/audio.sh – PipeWire audio stack installation
set -Eeuo pipefail

install_audio() {
    log_info "Installing PipeWire audio stack..."

    local pkgs=(
        pipewire
        pipewire-alsa
        pipewire-pulse
        pipewire-jack
        wireplumber
        gst-plugin-pipewire
        libpulse
        pavucontrol
        helvum
    )

    run_cmd_interactive pacman -S --noconfirm --needed "${pkgs[@]}"

    # PipeWire services activate automatically via KDE/XDG autostart on login.
    log_info "PipeWire audio stack installed."
}
