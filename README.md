# ArchInstall Framework

Modular Arch Linux installer written in Bash and designed for the Arch Linux live ISO.

## Quick Start (Arch ISO)

Run these commands from the Arch ISO before starting the installer:

```bash
pacman -Sy archlinux-keyring --noconfirm
pacman -S --needed --noconfirm dialog git reflector parted dosfstools e2fsprogs btrfs-progs
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
git clone https://github.com/emrecanymz9/archinstall-framework.git
cd archinstall-framework
bash installer/install.sh
```

Warning: the installer wipes the selected disk.

VM testing is strongly recommended before using it on real hardware.

## Features

- Dialog-based multi-menu navigation
- Disk discovery and target selection
- File-backed installer state in /tmp/archinstall_state
- Base system installation with pacstrap
- Safe error handling with confirmations and install logs

## Layout

```text
installer/
  disk.sh        Disk discovery and selection
  executor.sh    Base installation workflow
  install.sh     Main TUI entry point
  postinstall.sh Placeholder for future post-install hooks
  state.sh       Shared installer state helpers
  ui.sh          Reusable dialog wrappers
```

## Requirements

Run from an Arch Linux live ISO as root with these tools available:

```bash
pacman -Sy archlinux-keyring --noconfirm
pacman -S --needed --noconfirm dialog git reflector parted dosfstools e2fsprogs btrfs-progs arch-install-scripts
```

The installer also expects standard live ISO utilities such as lsblk, wipefs, mount, umount, ping, pacstrap, and genfstab.

## Usage

```bash
bash installer/install.sh
```

## Install Flow

1. Open Disk Setup and select the target disk.
2. Open Install System and start the base installation.
3. Confirm destructive actions when prompted.
4. The installer will:
  - verify network connectivity
  - refresh pacman mirrors with reflector
   - wipe the selected disk
   - create a GPT table
   - create a 512 MiB EFI partition and one root partition
   - format EFI as FAT32 and root as ext4
   - mount the target to /mnt
  - retry pacstrap up to three times
   - generate /etc/fstab

## Safety Notes

- The live ISO boot disk is excluded from the disk selection list when it can be detected.
- The installer refuses to run without root privileges.
- Installation errors are written to /tmp/archinstall_install.log and surfaced in dialog.
- Existing mounts under /mnt are unmounted before a new installation begins.
- Disk operations are destructive. Use a VM first.

## Makefile

```bash
make run
```

This runs the installer from the repository root.
