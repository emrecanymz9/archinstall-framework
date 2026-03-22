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
- Install profile prompts for hostname, timezone, locale, and user creation
- Automatic boot mode handling: systemd-boot for UEFI and GRUB for BIOS
- Filesystem selection with ext4 fallback or btrfs subvolumes (@ and @home)
- Optional zram swap via zram-generator
- Optional KDE Plasma desktop profile with SDDM or greetd
- PipeWire audio and Bluetooth support for desktop installs
- DEV_MODE toggle for switching between dialog gauge mode and live terminal logs
- Safe error handling with confirmations and install logs

## Layout

```text
installer/
  disk.sh        Disk discovery and selection
  executor.sh    Base installation workflow
  install.sh     Main TUI entry point
  modules/
    bootloader.sh  Boot mode helpers
    desktop.sh     Desktop profile helpers
    network.sh     Pacman and mirror bootstrap helpers
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
2. Open Install System and configure hostname, timezone, locale, and user.
3. Choose the root filesystem and whether to enable zram swap.
4. Optionally select the KDE Plasma desktop profile and choose SDDM or greetd.
5. Toggle DEV_MODE when you want live logs instead of the dialog gauge.
6. Start the installation.
7. Confirm destructive actions when prompted.
8. The installer will:
  - verify network connectivity
  - refresh pacman mirrors with reflector
   - wipe the selected disk
  - detect UEFI or BIOS boot mode automatically
  - create a GPT layout with EFI plus root for UEFI systems
  - create an MBR layout with a bootable root partition for BIOS systems
  - format the required partitions as ext4 or btrfs
  - create btrfs subvolumes @ and @home when btrfs is selected
  - mount btrfs with zstd compression when btrfs is selected
   - mount the target to /mnt
  - retry pacstrap up to three times
   - generate /etc/fstab
  - configure hostname, timezone, locale, NetworkManager, optional zram, and the primary user
  - optionally install KDE Plasma, explicit desktop packages, a display manager, PipeWire, and Bluetooth packages
  - enable SDDM or greetd when a desktop profile is selected
  - enable Bluetooth and PipeWire user services for desktop installs
  - install systemd-boot on UEFI or GRUB on BIOS

In dialog mode the installer now keeps package management outside the dialog pipeline. The install core runs in the background, a progress gauge shows fake progress, and a parallel log viewer tails `/tmp/archinstall_install.log`.

## Safety Notes

- The live ISO boot disk is excluded from the disk selection list when it can be detected.
- The installer refuses to run without root privileges.
- Installation errors are written to /tmp/archinstall_install.log and surfaced in dialog.
- Existing mounts under /mnt are unmounted before a new installation begins.
- Disk operations are destructive. Use a VM first.

## Makefile

```bash
make deps
make mirror
make run
make dev
make log
make clean
```

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

DEV_MODE=false is the default and uses the dialog progress gauge during installation.

```bash
bash installer/install.sh
```

DEV_MODE=true switches the installer to live terminal output for debugging.

```bash
DEV_MODE=true bash installer/install.sh
```

Live output is better for debugging. Gauge mode is quieter and better suited for normal installs.
