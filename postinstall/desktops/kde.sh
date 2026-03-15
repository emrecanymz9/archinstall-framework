#!/usr/bin/env bash
# postinstall/desktops/kde.sh – KDE Plasma 6 desktop install flow
# Called by postinstall/install.sh; can also be run standalone.
set -Eeuo pipefail

FRAMEWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export FRAMEWORK_ROOT
export LOG_FILE="${LOG_FILE:-/var/log/archinstall-phase2.log}"
export UI_BACKTITLE="${UI_BACKTITLE:-ArchInstall Framework — Post Install (KDE)}"

source "$FRAMEWORK_ROOT/installer/ui.sh"
source "$FRAMEWORK_ROOT/installer/state.sh"
source "$FRAMEWORK_ROOT/installer/executor.sh"

# ===========================================================================
# HELPER FUNCTIONS
# ===========================================================================

_configure_greetd() {
    local username
    username=$(get_state "username")

    mkdir -p /etc/greetd

    # Use autologin-like qtgreet config for the installed user
    cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "qtgreet"
user = "greeter"
EOF

    # Create greeter user if not exists
    id greeter &>/dev/null || useradd -r -s /usr/bin/nologin -d /var/lib/greeter greeter

    # qtgreet config
    mkdir -p /var/lib/greeter
    cat > /var/lib/greeter/qtgreet.ini <<EOF
[General]
NumPadDefault=false
RememberLastUser=true
LastUser=${username}

[Background]
Type=color
Color=#1a1a2e
EOF
    chown -R greeter:greeter /var/lib/greeter 2>/dev/null || true

    log_info "greetd + qtgreet configured."
}

# ===========================================================================
# MAIN KDE FLOW
# ===========================================================================
main_kde() {
    log_info "KDE Plasma 6 post-install starting. Log: $LOG_FILE"

    # ---------------------------------------------------------------------------
    # Step 1: Update pacman databases
    # ---------------------------------------------------------------------------
    log_step "Step 1: Updating package databases"
    run_cmd_interactive pacman -Sy --noconfirm

    # ---------------------------------------------------------------------------
    # Step 2: KDE Plasma 6 + Wayland stack
    # ---------------------------------------------------------------------------
    log_step "Step 2: KDE Plasma 6 + Wayland"

    KDE_PKGS=(
        # Plasma desktop
        plasma-meta
        kde-applications-meta
        # Wayland
        plasma-wayland-session
        xorg-xwayland
        # Display manager
        greetd
        greetd-qtgreet
        # Fonts
        noto-fonts noto-fonts-emoji ttf-liberation
        # System integration
        packagekit-qt6
        flatpak
        # Terminals
        konsole
    )

    run_cmd_interactive pacman -S --noconfirm --needed "${KDE_PKGS[@]}"

    # Configure greetd
    _configure_greetd

    # Enable display manager
    run_cmd systemctl enable greetd.service

    log_info "KDE Plasma 6 installed."

    # ---------------------------------------------------------------------------
    # Step 3: ZRAM (verify/configure)
    # ---------------------------------------------------------------------------
    log_step "Step 3: ZRAM configuration"
    source "$FRAMEWORK_ROOT/modules/zram.sh"
    configure_zram

    # ---------------------------------------------------------------------------
    # Step 4: Audio (PipeWire)
    # ---------------------------------------------------------------------------
    log_step "Step 4: PipeWire audio"
    source "$FRAMEWORK_ROOT/modules/audio.sh"
    install_audio

    # ---------------------------------------------------------------------------
    # Step 5: GPU drivers
    # ---------------------------------------------------------------------------
    log_step "Step 5: GPU drivers"
    source "$FRAMEWORK_ROOT/modules/gpu.sh"
    install_gpu_drivers

    # ---------------------------------------------------------------------------
    # Step 6: Network tools
    # ---------------------------------------------------------------------------
    log_step "Step 6: Network tools"
    source "$FRAMEWORK_ROOT/modules/network.sh"
    install_network_tools

    # ---------------------------------------------------------------------------
    # Step 7: Bluetooth
    # ---------------------------------------------------------------------------
    log_step "Step 7: Bluetooth"
    source "$FRAMEWORK_ROOT/modules/bluetooth.sh"
    install_bluetooth

    # ---------------------------------------------------------------------------
    # Step 8: Gaming tools
    # ---------------------------------------------------------------------------
    log_step "Step 8: Gaming tools"
    source "$FRAMEWORK_ROOT/modules/gaming.sh"
    install_gaming

    # ---------------------------------------------------------------------------
    # Step 9: Dev + cybersec tools
    # ---------------------------------------------------------------------------
    log_step "Step 9: Dev and cybersec tools"
    source "$FRAMEWORK_ROOT/modules/devtools.sh"
    install_devtools

    # ---------------------------------------------------------------------------
    # Step 10: Backup / snapshot tools
    # ---------------------------------------------------------------------------
    log_step "Step 10: Backup and snapshot tools"
    source "$FRAMEWORK_ROOT/modules/backup.sh"
    install_backup

    # ---------------------------------------------------------------------------
    # Step 11: Secure Boot (sbctl) – instructions + optional automation
    # ---------------------------------------------------------------------------
    log_step "Step 11: Secure Boot"
    source "$FRAMEWORK_ROOT/modules/secureboot.sh"
    setup_secureboot

    log_info "KDE Plasma 6 post-install complete."
}

# ---------------------------------------------------------------------------
# Run main_kde when executed directly (not sourced)
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        echo "ERROR: This script must run as root."
        exit 1
    fi
    main_kde
fi
