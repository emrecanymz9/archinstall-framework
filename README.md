# ArchInstall Framework

Modular Arch Linux installer written in Bash for the Arch Linux live ISO.

Warning: destructive installs are still possible. The disk manager now supports full-disk wipe, free-space installs, dual-boot preparation, and manual partition reuse, but you should still test in a VM before touching real hardware.

## Quick Start

Run these commands from the Arch ISO as root:

```bash
loadkeys us
setfont ter-v16n
pacman-key --init
pacman-key --populate archlinux
pacman -Sy archlinux-keyring --noconfirm
pacman -S --needed --noconfirm git dialog reflector
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
git clone https://github.com/emrecanymz9/archinstall-framework.git
cd archinstall-framework
bash installer/install.sh
```

The installer intentionally keeps the live ISO minimal. Heavy packages belong in the target system through `pacstrap`, not in the RAM-backed ISO environment.

## Features

- dialog-based install flow
- runtime-aware UI with boot-mode, Secure Boot, and environment detection
- ext4 and btrfs root installs
- SSD, HDD, and NVMe mount-option detection
- disk-space validation on `/mnt` before `pacstrap`
- disk manager with full-wipe, free-space, dual-boot, and manual strategies
- UEFI with systemd-boot or BIOS with GRUB
- Secure Boot modes: `Disabled`, `Assisted`, `Advanced`
- hardware abstraction for VMware, VirtualBox, QEMU/KVM, and common GPU vendors
- optional zram via `zram-generator`
- config-driven package tiers from `config/system.conf`
- KDE Plasma profile with both Wayland and X11 session support
- install profiles: `DAILY`, `DEV`, `CUSTOM`
- display mode selection: `Auto`, `Wayland`, `X11`
- `greetd` with `tuigreet` by default and optional `qtgreet`
- plugin hooks for packages, chroot snippets, and menu extensions
- pacman-key and mirror bootstrap hardening
- install log at `/tmp/archinstall_install.log`
- mixed-gauge dialog progress view with recent log lines

Additional documentation:

- `docs/ARCHITECTURE.md`
- `docs/DISK_MANAGER.md`
- `docs/SECURE_BOOT.md`
- `docs/HARDWARE.md`
- `docs/PROFILES.md`
- `docs/INSTALL_FLOW.md`
- `docs/PLUGINS.md`

## Live ISO Rules

Safe console defaults:

```bash
loadkeys us
setfont ter-v16n
```

Why the installer avoids large ISO-side package installs:

- the Arch ISO root filesystem is RAM-backed
- large toolchains can exhaust `/` and destabilize the session
- `base-devel` should be installed into the target system, not the live ISO
- `make full-deps` is for development machines, not the normal ISO workflow

## Requirements

Minimal live ISO packages:

```bash
pacman -Sy archlinux-keyring --noconfirm
pacman -S --needed --noconfirm git dialog reflector
```

The installer expects the normal Arch ISO tooling already present, including `lsblk`, `wipefs`, `mount`, `umount`, `parted`, `pacstrap`, `blkid`, and `arch-chroot`.

## Usage

Run directly:

```bash
bash installer/install.sh
```

Or use the helpers:

```bash
make deps
make mirror
make run
```

For non-ISO development machines:

```bash
make full-deps
```

Developer mode keeps terminal output visible:

```bash
DEV_MODE=true bash installer/install.sh
```

## Install Flow

1. Open `Disk Setup` and choose the install target.
2. Open `Install System`.
3. Configure:
   - hostname
   - timezone
   - locale
   - keyboard layout
   - username
   - user password
   - root password
  - install profile
   - filesystem
   - zram preference
  - Secure Boot mode
   - desktop profile
   - display mode
   - display manager
4. Confirm the destructive summary.
5. Watch the live mixed-gauge progress window.
6. Choose `Reboot`, `Shutdown`, or `Back` after completion.

At startup the installer applies:

- `loadkeys us`
- optional live keymap override
- `setfont ter-v16n`

## KDE Session Modes

The KDE profile installs `plasma-workspace` and `plasma-x11-session`.

Display mode choices:

- `Auto`: prefer Wayland, fall back to X11 on VMs or when graphics detection is weak
- `Wayland`: force `startplasma-wayland`
- `X11`: force `startplasma-x11`

Current display-manager behavior:

- `greetd`: default display manager for Plasma installs
- `tuigreet`: default frontend and always supported by the built-in package set
- `qtgreet`: optional frontend for KDE-oriented deployments when a plugin or custom package source provides it
- greetd always launches Plasma on Wayland and leaves X11 available as a manual fallback helper
- invalid or missing display-manager binaries leave the system on TTY with a manual start hint

## Package Set

The target install always includes the base packages requested in this hardening pass:

- `base`
- `base-devel`
- `linux`
- `linux-firmware`
- `make`
- `networkmanager`
- `sudo`
- `git`
- `dialog`

The KDE profile additionally installs Plasma, PipeWire, Bluetooth, and the selected display manager.

## Filesystem Notes

### ext4

- root is formatted as ext4
- root is mounted with disk-aware options
- SSD and NVMe paths add `noatime,discard=async`
- HDD avoids `discard=async`

### btrfs

- creates `@` and `@home`
- mounts `/` with `subvol=@,compress=zstd`
- mounts `/home` with `subvol=@home,compress=zstd`
- writes explicit UUID-based `fstab` entries
- uses matching `rootflags=` in the bootloader entry

## Bootloader Notes

### UEFI

- installs `systemd-boot`
- writes `/boot/loader/entries/arch.conf`
- uses UUID-based root parameters

### BIOS

- installs GRUB
- writes `GRUB_CMDLINE_LINUX` with UUID-based root parameters

## Robustness Rules

Hard failures:

- partitioning errors
- mount errors
- pacman bootstrap failures
- insufficient target free space
- `pacstrap` failures
- essential chroot configuration failures

Best-effort logging steps:

- `blkid` debug output
- `findmnt` debug output
- supplemental metadata capture

## Logs And Debugging

Primary log file:

```text
/tmp/archinstall_install.log
```

Useful checks:

```bash
less /tmp/archinstall_install.log
grep -n "\[FAIL\]\|\[WARN\]\|\[DEBUG\]" /tmp/archinstall_install.log
df -h /
df -h /mnt
```

## Troubleshooting

### Pacstrap fails

- confirm the live ISO has network access
- inspect `/tmp/archinstall_install.log`
- rerun the mirror refresh with `reflector`

### Installer reports low target space

- inspect `df -h /mnt`
- reduce the target profile or resize the target partition
- do not continue into `pacstrap` with an undersized root filesystem

### KDE boots to TTY

- inspect `/tmp/archinstall_install.log`
- verify the selected display manager exists in the target system
- start Plasma manually with the command shown on login

### greetd works but the wrong session starts

- check the saved `Display mode` value in the installer state
- for VMs, `Auto` may intentionally resolve to X11
- choose `Wayland` or `X11` explicitly if you need deterministic behavior

## Layout

```text
installer/
  disk.sh        Disk discovery and selection
  executor.sh    Install core and chroot configuration
  install.sh     Main dialog UI entry point
  modules/
    bootloader.sh   Boot mode helpers
    desktop.sh      Desktop profile helpers
    network.sh      Live ISO pacman bootstrap helpers
    profile.sh      Timezone, locale, and keymap selection helpers
    disk/
      layout.sh     Partition-path helpers for future disk layout expansion
      space.sh      Target free-space estimation and checks
  postinstall.sh Placeholder for future post-install hooks
  state.sh       Shared installer state helpers
  ui.sh          Reusable dialog wrappers
```

## Makefile

```bash
make deps
make full-deps
make mirror
make run
make dev
make log
make clean
```

`make deps` installs the minimal ISO-side tools:

- `git`
- `dialog`
- `reflector`

`make full-deps` adds development tooling such as `base-devel`, `parted`, `dosfstools`, `e2fsprogs`, `btrfs-progs`, and `arch-install-scripts`.
