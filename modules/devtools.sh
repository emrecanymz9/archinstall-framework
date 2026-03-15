#!/usr/bin/env bash
# modules/devtools.sh – Development and cybersecurity tools
set -Eeuo pipefail

install_devtools() {
    log_info "Installing development and cybersecurity tools..."

    local pkgs=(
        # Editors
        neovim
        vim
        code

        # Development
        git
        base-devel
        cmake
        clang
        llvm
        python
        python-pip
        nodejs
        npm
        go
        rustup
        docker
        docker-compose

        # Terminals / Shell
        tmux
        zsh
        zsh-completions
        zsh-autosuggestions
        zsh-syntax-highlighting
        starship

        # Utilities
        fzf
        ripgrep
        fd
        bat
        eza
        htop
        btop
        jq
        yq

        # Network tools / Cybersec
        nmap
        wireshark-qt
        tcpdump
        netcat
        metasploit
        john
        hashcat
        gobuster
        sqlmap
        aircrack-ng
        nikto

        # VPN
        wireguard-tools
        openvpn
    )

    run_cmd_interactive pacman -S --noconfirm --needed "${pkgs[@]}"

    # Add user to docker group
    local username
    username=$(get_state "username")
    if [[ -n "$username" ]]; then
        usermod -aG docker,wireshark "$username" 2>/dev/null || true
    fi

    run_cmd systemctl enable docker.service

    # Install rustup stable toolchain (best-effort; user can run manually if needed)
    if command -v rustup &>/dev/null; then
        run_cmd rustup default stable || log_warn "rustup toolchain install failed; run 'rustup default stable' manually."
    fi

    log_info "Dev and cybersec tools installed."
}