# ArchInstall Framework

Modular Arch Linux installer written in Bash for the Arch Linux live ISO.

The installer targets a small, explicit workflow:

- dialog-based navigation
- ext4 or btrfs root installation
- optional zram
- UEFI with systemd-boot or BIOS with GRUB
- live install logs in dialog without gauge mode
- explicit fstab generation and bootloader configuration

Warning: the installer wipes the selected disk.

VM testing is strongly recommended before using it on real hardware.

## Quick Start

Run these commands from the Arch ISO as root:

```bash
pacman -Sy archlinux-keyring --noconfirm
pacman -S --needed --noconfirm base-devel dialog git reflector parted dosfstools e2fsprogs btrfs-progs arch-install-scripts
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
git clone https://github.com/emrecanymz9/archinstall-framework.git
cd archinstall-framework
bash installer/install.sh
```

If `make` is missing and you want to use the Makefile helpers first:

```bash
pacman -S --needed --noconfirm base-devel
```

## Features

- dialog-based multi-menu navigation
- disk discovery with destructive action confirmation
- explicit ext4 and btrfs installation paths
- btrfs `@` and `@home` subvolumes with `compress=zstd`
- UUID-based fstab generation
- separate user password and root password prompts
- timezone, locale, and keyboard-layout selection with custom input
- optional KDE Plasma profile
- SDDM support
- greetd configuration path for qtgreet
- zram support through `zram-generator`
- live install log view through `dialog --tailbox`
- install logging in `/tmp/archinstall_install.log`

## Layout

```text
installer/
  disk.sh        Disk discovery and selection
  executor.sh    Install core and chroot configuration
  install.sh     Main dialog UI entry point
  modules/
    bootloader.sh  Boot mode helpers
    desktop.sh     Desktop profile helpers
    network.sh     Live ISO pacman bootstrap helpers
    profile.sh     Timezone, locale, and keymap selection helpers
  postinstall.sh Placeholder for future post-install hooks
  state.sh       Shared installer state helpers
  ui.sh          Reusable dialog wrappers
```

## Requirements

Run from an Arch Linux live ISO as root with these tools available:

```bash
pacman -Sy archlinux-keyring --noconfirm
pacman -S --needed --noconfirm base-devel dialog git reflector parted dosfstools e2fsprogs btrfs-progs arch-install-scripts
```

The installer also expects standard live ISO utilities such as `lsblk`, `wipefs`, `mount`, `umount`, `ping`, `pacstrap`, `blkid`, and `arch-chroot`.

## Usage

Run the installer directly:

```bash
bash installer/install.sh
```

Or use the Makefile helpers:

```bash
make deps
make mirror
make run
```

Developer mode keeps the plain shell output visible:

```bash
DEV_MODE=true bash installer/install.sh
```

## Install Flow

1. Open Disk Setup and select the target disk.
2. Open Install System.
3. Configure:
  - hostname
  - timezone
  - locale
  - keyboard layout
  - username
  - user password
  - root password
  - filesystem
  - zram preference
  - desktop profile
  - display manager
4. Confirm the destructive install summary.
5. Watch the live install log window.
6. After completion, choose `Reboot`, `Shutdown`, or `Back`.

## Configuration Examples

Timezone examples:

```text
Europe/Istanbul
UTC
Europe/Berlin
Europe/London
America/New_York
```

Locale examples:

```text
en_US.UTF-8
tr_TR.UTF-8
en_GB.UTF-8
de_DE.UTF-8
```

Keyboard layout examples:

```text
us
trq
trf
uk
de-latin1
fr-latin9
```

## Filesystem Notes

### ext4

- root is formatted as ext4
- root is mounted directly at `/mnt`
- fstab is written with a UUID root entry

### btrfs

- root is formatted with `mkfs.btrfs`
- installer mounts the top-level volume first
- installer creates `@` and `@home`
- installer remounts `/` with `subvol=@,compress=zstd`
- installer mounts `/home` with `subvol=@home,compress=zstd`
- fstab is written explicitly with UUID entries for `/` and `/home`

## Bootloader Notes

### UEFI

- installs `systemd-boot`
- writes `/boot/loader/entries/arch.conf`
- uses `root=UUID=...`
- adds `rootflags=subvol=@,compress=zstd` for btrfs

### BIOS

- installs GRUB
- writes `GRUB_CMDLINE_LINUX` with `root=UUID=...`
- adds `rootflags=subvol=@,compress=zstd` for btrfs

## Desktop Notes

### SDDM

Recommended for the default zero-touch KDE path.

### greetd + qtgreet

The installer now wires greetd configuration for qtgreet, but `qtgreet` is not shipped in the official Arch repositories.

Important:

- the Arch-compatible package path is the AUR package `greetd-qtgreet`
- the installer does not build the full AUR dependency chain automatically
- if you want the most reliable fully non-interactive desktop install, choose `sddm`
- if you choose `greetd`, the installer configures greetd for qtgreet and logs a warning if `/usr/bin/qtgreet` is missing

## Robustness Rules

The install core treats these as hard failures:

- partitioning errors
- mount errors
- pacstrap errors
- essential chroot configuration failures

The install core treats these as warnings and continues:

- `findmnt` debug logging
- `blkid` debug logging
- mirror refresh and other best-effort live ISO preparation steps
- optional UI/logging behavior

## Logs And Debugging

Primary log file:

```text
/tmp/archinstall_install.log
```

Open the log during or after install:

```bash
less /tmp/archinstall_install.log
```

Useful log searches:

```bash
grep -n "\[FAIL\]\|\[WARN\]\|\[DEBUG\]" /tmp/archinstall_install.log
grep -n "fstab\|loader\|grub\|blkid\|findmnt" /tmp/archinstall_install.log
```

## Rerunning An Install

If a test install fails and you want to rerun it from the live ISO:

```bash
umount -R /mnt || true
rm -f /tmp/archinstall_state
rm -f /tmp/archinstall_install.log
bash installer/install.sh
```

For faster menu testing without a full reinstall:

```bash
DEV_MODE=true SKIP_PARTITION=true SKIP_PACSTRAP=true SKIP_CHROOT=true bash installer/install.sh
```

## Troubleshooting

### Installer stops during partitioning or mounting

- verify the selected disk is correct
- confirm the disk is not the live ISO boot device
- check `lsblk` before rerunning

### Pacstrap fails

- confirm network access from the live ISO
- refresh mirrors again with `reflector`
- inspect `/tmp/archinstall_install.log`

### System boots but drops into emergency mode

- inspect the installed `/etc/fstab`
- confirm the bootloader entry uses the correct `UUID`
- for btrfs, confirm `rootflags=subvol=@,compress=zstd` is present

### Root account is locked message appears

- verify the root password was entered during profile setup
- inspect the chroot section in `/tmp/archinstall_install.log`
- rerun after confirming the password prompts completed successfully

### greetd starts but no graphical greeter appears

- check whether `/usr/bin/qtgreet` exists in the target system
- if it does not, install the AUR package `greetd-qtgreet`
- if you want the simpler path, use `sddm`

## Makefile

```bash
make deps
make mirror
make run
make dev
make log
make clean
```

`make deps` installs:

- `base-devel`
- `dialog`
- `git`
- `reflector`
- `parted`
- `dosfstools`
- `e2fsprogs`
- `btrfs-progs`
- `arch-install-scripts`
