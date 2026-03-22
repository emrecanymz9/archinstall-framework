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

## 🚀 Full Installation (Bootable System)

The installer now builds a bootable Arch Linux system from the live ISO workflow.

It includes:

- disk partitioning
- base system installation
- chroot configuration
- UEFI bootloader installation with systemd-boot

During the install flow the project will:

- wipe and partition the selected disk unless partitioning is skipped explicitly
- install the base Arch packages
- generate `/etc/fstab`
- configure timezone, locale, hostname, hosts, and the root password
- install and enable NetworkManager
- install `systemd-boot` and create a boot entry that uses the root `PARTUUID`

### ⚡ Dev Mode (Fast Testing)

The installer supports fast testing through environment flags in `installer/executor.sh`:

```bash
SKIP_PARTITION=true SKIP_PACSTRAP=true bash installer/install.sh
```

Available flags:

- `DEV_MODE=true`
- `SKIP_PARTITION=true`
- `SKIP_PACSTRAP=true`
- `SKIP_CHROOT=true`

These flags skip destructive or time-consuming phases and make it easier to test the menu flow and installer logic without rerunning the full Arch installation every time.

## 🎛️ Installer UI Modes

Default plain mode shows the full terminal output during installation.

```bash
bash installer/install.sh
```

Dialog mode uses a progress bar during the long-running install stage.

```bash
INSTALL_UI_MODE=dialog bash installer/install.sh
```

Dialog mode hides most logs while the progress bar is active, so it is less useful for debugging than the default plain mode.
