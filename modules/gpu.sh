#!/usr/bin/env bash
# modules/gpu.sh – GPU driver detection and installation
set -Eeuo pipefail

install_gpu_drivers() {
    log_info "Detecting GPU..."

    local gpu_vendor=""
    if lspci 2>/dev/null | grep -qi "NVIDIA"; then
        gpu_vendor="nvidia"
    elif lspci 2>/dev/null | grep -qi "AMD\|Radeon\|ATI"; then
        gpu_vendor="amd"
    elif lspci 2>/dev/null | grep -qi "Intel.*Graphics\|Intel.*Display"; then
        gpu_vendor="intel"
    else
        log_warn "GPU vendor not detected; installing mesa as fallback."
        gpu_vendor="generic"
    fi

    log_info "GPU vendor: $gpu_vendor"

    case "$gpu_vendor" in
        nvidia)
            _install_nvidia
            ;;
        amd)
            _install_amd
            ;;
        intel)
            _install_intel
            ;;
        generic)
            run_cmd_interactive pacman -S --noconfirm --needed mesa vulkan-swrast
            ;;
    esac
}

_install_nvidia() {
    log_info "Installing NVIDIA drivers..."

    local choice
    choice=$(ui_radiolist "NVIDIA Driver" \
        "Choose the NVIDIA driver type:" \
        "proprietary" "NVIDIA proprietary drivers (recommended for gaming)" "on" \
        "nouveau"     "Nouveau open-source drivers (limited 3D, no CUDA)"   "off" \
    ) || choice="proprietary"

    if [[ "$choice" == "proprietary" ]]; then
        run_cmd_interactive pacman -S --noconfirm --needed \
            nvidia-dkms nvidia-utils nvidia-settings lib32-nvidia-utils \
            opencl-nvidia libvdpau libglvnd

        # Enable DRM kernel mode setting for Wayland
        mkdir -p /etc/modprobe.d
        echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia-drm.conf
        echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" \
            >> /etc/modprobe.d/nvidia-drm.conf
        log_info "NVIDIA proprietary drivers installed. DRM modeset enabled."
    else
        run_cmd_interactive pacman -S --noconfirm --needed \
            xf86-video-nouveau mesa lib32-mesa
        log_info "Nouveau drivers installed."
    fi
}

_install_amd() {
    log_info "Installing AMD drivers..."
    run_cmd_interactive pacman -S --noconfirm --needed \
        mesa lib32-mesa \
        vulkan-radeon lib32-vulkan-radeon \
        libva-mesa-driver lib32-libva-mesa-driver \
        mesa-vdpau lib32-mesa-vdpau \
        xf86-video-amdgpu
    log_info "AMD drivers installed."
}

_install_intel() {
    log_info "Installing Intel drivers..."
    run_cmd_interactive pacman -S --noconfirm --needed \
        mesa lib32-mesa \
        vulkan-intel lib32-vulkan-intel \
        intel-media-driver \
        libvdpau-va-gl
    log_info "Intel drivers installed."
}
