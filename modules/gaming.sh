#!/usr/bin/env bash
# modules/gaming.sh - Gaming tools: Steam, GameMode, MangoHud, Lutris, Wine
set -Eeuo pipefail

install_gaming() {
    log_info "Installing gaming tools..."

    # Ensure multilib is enabled
    _enable_multilib

    local pkgs=(
        # Steam (native)
        steam
        # Gaming optimizations
        gamemode
        lib32-gamemode
        gamescope
        mangohud
        lib32-mangohud
        # Lutris + Wine
        lutris
        wine-staging
        wine-gecko
        wine-mono
        winetricks
        # Vulkan
        vulkan-tools
        vulkan-icd-loader
        lib32-vulkan-icd-loader
        # OpenAL (audio in games)
        openal
        lib32-openal
        # Proton dependencies
        vkd3d
        lib32-vkd3d
    )

    run_cmd_interactive pacman -S --noconfirm --needed "${pkgs[@]}"

    # Enable GameMode daemon
    if ! run_cmd systemctl enable gamemoded.service 2>/dev/null; then
        log_warn "gamemoded.service not found; GameMode daemon will not autostart."
    fi

    # Configure GameMode for the user
    local username
    username=$(get_state "username")
    if [[ -n "$username" ]]; then
        usermod -aG gamemode "$username" 2>/dev/null || true
    fi

    log_info "Gaming tools installed."
}

_enable_multilib() {
    local pacman_conf="/etc/pacman.conf"
    if ! grep -q "^\[multilib\]" "$pacman_conf"; then
        sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' "$pacman_conf"
        run_cmd pacman -Sy --noconfirm
        log_info "Multilib repository enabled."
    fi
}