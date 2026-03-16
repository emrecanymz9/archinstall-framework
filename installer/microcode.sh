#!/usr/bin/env bash
# installer/microcode.sh - CPU microcode detection and installation
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# detect_microcode  ->  sets MICROCODE ("intel-ucode"|"amd-ucode"|"")
# ---------------------------------------------------------------------------
detect_microcode() {
    if grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        MICROCODE="intel-ucode"
    elif grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        MICROCODE="amd-ucode"
    else
        MICROCODE=""
    fi
    set_state_str "microcode" "${MICROCODE:-none}"
    log_info "Microcode package: ${MICROCODE:-none}"
}

# ---------------------------------------------------------------------------
# install_microcode  ->  installs the detected microcode package in chroot
# ---------------------------------------------------------------------------
install_microcode() {
    detect_microcode
    if [[ -n "${MICROCODE:-}" ]]; then
        log_step "Installing microcode: $MICROCODE"
        chroot_run "pacman -S --noconfirm --needed $MICROCODE"
    else
        log_info "No microcode package needed (unknown or virtual CPU)."
    fi
}
