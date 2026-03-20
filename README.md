# ArchInstall Framework

Modular Arch Linux installer written in Bash and designed for the Arch Linux live ISO.

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
pacman -Sy --needed dialog parted dosfstools e2fsprogs arch-install-scripts
```

The installer also expects standard live ISO utilities such as lsblk, wipefs, mount, umount, and arch-chroot.

## Usage

```bash
./installer/install.sh
```

## Install Flow

1. Open Disk Setup and select the target disk.
2. Open Install System and start the base installation.
3. Confirm destructive actions when prompted.
4. The installer will:
   - wipe the selected disk
   - create a GPT table
   - create a 512 MiB EFI partition and one root partition
   - format EFI as FAT32 and root as ext4
   - mount the target to /mnt
   - install base packages with pacstrap
   - generate /etc/fstab
   - enable NetworkManager in the target system

## Safety Notes

- The live ISO boot disk is excluded from the disk selection list when it can be detected.
- The installer refuses to run without root privileges.
- Installation errors are written to /tmp/archinstall_install.log and surfaced in dialog.
- Existing mounts under /mnt are unmounted before a new installation begins.

## Makefile

```bash
make run
```

This runs the installer from the repository root.
