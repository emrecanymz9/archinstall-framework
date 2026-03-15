#!/usr/bin/env bash
# modules/network.sh – Network configuration and tools
set -Eeuo pipefail

install_network_tools() {
    log_info "Installing network tools..."

    local pkgs=(
        networkmanager
        network-manager-applet
        nm-connection-editor
        nss-mdns
        wget
        curl
        bind-tools
        openssh
        rsync
        net-tools
        inetutils
    )

    run_cmd_interactive pacman -S --noconfirm --needed "${pkgs[@]}"

    # Enable NetworkManager (should already be enabled from Phase 1, but ensure)
    run_cmd systemctl enable NetworkManager.service
    run_cmd systemctl enable systemd-resolved.service

    # Configure nsswitch for mDNS
    sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' \
        /etc/nsswitch.conf 2>/dev/null || true

    log_info "Network tools installed."
}
