#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Ensure running as root (Arch ISO is root by default)
# --------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Run this installer as root."
    exit 1
fi

# --------------------------------------------------
# Fix permissions (in case cloned from Windows)
# --------------------------------------------------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
find "$PROJECT_ROOT" -type f -name "*.sh" -exec chmod +x {} \;

# --------------------------------------------------
# Source core modules
# --------------------------------------------------

# Resolve script directory safely
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Load modules
source "$SCRIPT_DIR/ui.sh"
source "$SCRIPT_DIR/state.sh"
source "$SCRIPT_DIR/bootmode.sh"
source "$SCRIPT_DIR/disk.sh"
source "$SCRIPT_DIR/filesystem.sh"
source "$SCRIPT_DIR/luks.sh"
source "$SCRIPT_DIR/limine.sh"
source "$SCRIPT_DIR/microcode.sh"
source "$SCRIPT_DIR/executor.sh"

# --------------------------------------------------
# Dependency check
# --------------------------------------------------
require_tools

for cmd in lsblk parted cryptsetup pacstrap genfstab; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "$cmd is required."
        exit 1
    }
done

# --------------------------------------------------
# Initialize state
# --------------------------------------------------
init_state

# --------------------------------------------------
# Boot mode lock
# --------------------------------------------------
bootmode_screen

# --------------------------------------------------
# Disk selection
# --------------------------------------------------
TARGET_DISK=$(select_disk)

if [[ -z "$TARGET_DISK" ]]; then
    clear
    exit 1
fi

set_state target_disk "\"$TARGET_DISK\""

# --------------------------------------------------
# Partition table detection
# --------------------------------------------------
PART_TABLE=$(get_partition_table "$TARGET_DISK")
set_state partition_table "\"$PART_TABLE\""

# --------------------------------------------------
# Windows detection
# --------------------------------------------------
if detect_windows "$TARGET_DISK"; then
    set_state windows_detected true
else
    set_state windows_detected false
fi

# --------------------------------------------------
# Installation mode
# --------------------------------------------------
INSTALL_MODE=$(choose_install_mode "$TARGET_DISK")

if [[ -z "$INSTALL_MODE" ]]; then
    clear
    exit 1
fi

set_state install_mode "\"$INSTALL_MODE\""

# --------------------------------------------------
# Final destructive confirmation
# --------------------------------------------------
dialog --inputbox \
"Type the disk name to confirm installation:\n\n$TARGET_DISK" \
10 60 2> /tmp/confirm.txt

CONFIRM=$(cat /tmp/confirm.txt)

if [[ "$CONFIRM" != "$TARGET_DISK" ]]; then
    clear
    echo "Confirmation failed."
    exit 1
fi

clear
echo "Starting installation..."

# --------------------------------------------------
# Execution phase
# --------------------------------------------------

if [[ "$INSTALL_MODE" == "wipe" ]]; then
    create_gpt_layout "$TARGET_DISK"
else
    echo "Free space install not yet implemented."
    exit 1
fi

# Encryption
setup_luks "$ROOT_PART"

# Filesystem
setup_btrfs "$ROOT_MAPPED"

# Mount EFI
mount_efi

# Base install
install_base

# Microcode
install_microcode

# Limine
install_limine

echo "Installation complete."
