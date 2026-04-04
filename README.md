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
pacman -Sy --noconfirm make git dialog reflector
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
git clone https://github.com/emrecanymz9/archinstall-framework.git
cd archinstall-framework
bash installer/install.sh
```

### Full Install Command

From the Arch ISO as `root`:

```bash
loadkeys us
setfont ter-v16n
pacman-key --init
pacman-key --populate archlinux
pacman -Sy archlinux-keyring --noconfirm
pacman -Sy --noconfirm make git dialog reflector
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
git clone https://github.com/emrecanymz9/archinstall-framework.git
cd archinstall-framework
bash installer/install.sh
```

### Profile-Based Examples

The installer is interactive. Start it, then choose the profile in `Install System -> Configure`.

- `DAILY`: full workstation defaults with KDE and common tools
- `DEV`: development-oriented toolset with a leaner package set
- `CUSTOM`: choose editor, VS Code, tools, desktop, and display behavior manually

Example launch for a `DAILY` install:

```bash
cd archinstall-framework
bash installer/install.sh
```

Then select `Install System`, open `Configure`, and choose `DAILY`.

Example launch for a `DEV` install:

```bash
cd archinstall-framework
bash installer/install.sh
```

Then select `Install System`, open `Configure`, and choose `DEV`.

### One-Line Curl Installer

This downloads the repository archive, extracts it, and launches the installer:

```bash
curl -fsSL https://github.com/emrecanymz9/archinstall-framework/archive/refs/heads/main.tar.gz | tar -xz && cd archinstall-framework-main && bash installer/install.sh
```

The installer intentionally keeps the live ISO minimal. Heavy packages belong in the target system through `pacstrap`, not in the RAM-backed ISO environment.

## Features

- dialog-based install flow
- runtime-aware UI with boot-mode, Secure Boot, and environment detection
- ext4 and btrfs root installs
- SSD, HDD, and NVMe mount-option detection
- disk-space validation on `/mnt` before `pacstrap`
- disk manager with full-wipe, free-space, dual-boot, and manual strategies
- bootloader support for `systemd-boot`, `GRUB`, and `Limine`
- Secure Boot modes: `Disabled`, `Setup Foundation`
- hardware abstraction for VMware, VirtualBox, QEMU/KVM, and common GPU vendors
- CPU microcode auto-detected and installed (`intel-ucode` or `amd-ucode`)
- GPU-aware graphics packages for Intel, AMD, NVIDIA, and virtualized desktops
- optional Steam support with multilib enablement and matching 32-bit graphics userspace
- optional zram via `zram-generator`
- config-driven package tiers from `config/packages.conf`
- KDE Plasma profile with both Wayland and X11 session support
- install profiles: `DAILY`, `DEV`, `CUSTOM`
- automatic `sudo` setup with `wheel` group support
- deterministic display session selection: `Wayland` or `X11`
- display managers: `greetd` with `tuigreet` or optional `qtgreet`, or `sddm` (recommended for KDE)
- `iwd` Wi-Fi backend configured automatically when installed
- btrfs four-subvolume layout: `@`, `@home`, `@var`, `@snapshots`
- snapper timeline snapshots with automatic cleanup timers
- `grub-btrfs` included only for BIOS/GRUB installs
- Secure Boot foundation mode for UKI + `sbctl` preparation without making install success depend on signing
- 1 GiB EFI partition enforced on new wipe/free-space installs
- EFI validation on manual partition reuse (size and filesystem warnings)
- BIOS + GPT safety check blocks unsafe grub-install scenarios
- pacstrap run with `-K` (target keyring initialisation)
- install manifest written to user home after successful install
- plugin hooks for packages, chroot snippets, and menu extensions
- pacman-key and mirror bootstrap hardening
- install log at `/tmp/archinstall_install.log`
- mixed-gauge dialog progress view with recent log lines

## Project Layout

Canonical installer layout:

- `installer/core/`
- `installer/modules/`
- `installer/features/`
- `installer/boot/`
- `installer/postinstall/`

Compatibility wrappers remain in older module paths where needed, but new bootloader, feature, and post-install behavior lives in those directories.

Additional documentation:

- `docs/ARCHITECTURE.md`
- `docs/FEATURES.md`
- `docs/STATE.md`
- `docs/DISK_MANAGER.md`
- `docs/INSTALL_FLOW.md`
- `docs/SECURE_BOOT.md`
- `docs/HARDWARE.md`

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
pacman -Sy --noconfirm make git dialog reflector
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
make install
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

Repository cleanup:

```bash
make clean
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

- `Wayland`: force `startplasma-wayland`
- `X11`: force `startplasma-x11`

Current display-manager behavior:

- `greetd`: GTK-based display manager; `tuigreet` is the default frontend
- `tuigreet`: TUI frontend for greetd, always supported by the built-in package set
- `qtgreet`: optional Qt/QML frontend for greetd when a plugin or custom package source provides it
- `sddm`: Qt-based display manager, recommended for KDE; installs `sddm` and `sddm-kcm`; writes `/etc/sddm.conf.d/kde_settings.conf` with Breeze theme defaults
- greetd launches the explicitly selected Plasma session command
- invalid or missing display-manager binaries leave the system on TTY with a manual start hint

## Bootloaders

Supported bootloaders:

- `systemd-boot`
- `GRUB`
- `Limine`

`BOOTLOADER` is stored in installer state and defaults deterministically from boot mode:

- `uefi` -> `systemd-boot`
- `bios` -> `grub`

Limine support writes `/boot/limine.cfg`, reuses the shared kernel command-line builder, and supports the same root UUID, LUKS, and btrfs rootflags flow as the other bootloaders.

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

Required packages are resolved in layers:

1. Required base: `sudo`, `networkmanager`, `iwd`, `iptables-nft`, `dialog`, `make`
2. Filesystem: `btrfs-progs` (btrfs) or nothing extra (ext4)
3. Profile packages from `DAILY`, `DEV`, or `CUSTOM`
4. Hardware: CPU microcode (`intel-ucode` or `amd-ucode`), GPU drivers, VM guest tools
5. Desktop profile: Plasma, PipeWire stack, Bluetooth, display manager
6. Snapshot tools: `snapper`, `snap-pac`, `grub-btrfs` (BIOS only)
7. Optional: `steam`, `zram-generator`, LUKS2 tools, Secure Boot tools
8. Plugin-contributed packages from the plugin loader

## Post-Install Pipeline

After pacstrap, the installer runs a structured post-install phase inside the chroot:

1. `finalize.sh` applies hostname, locale, timezone, sudo, and user configuration.
2. `enable_services.sh` enables NetworkManager, iwd, the selected display manager, and snapper timers when needed.
3. the selected bootloader is installed.
4. Secure Boot setup runs when requested.
5. `cleanup.sh` removes installer temp files from the target.

## Filesystem Notes

### ext4

- root is formatted as ext4
- root is mounted with disk-aware options
- SSD and NVMe paths add `noatime,discard=async`
- HDD avoids `discard=async`

### btrfs

- creates four subvolumes: `@`, `@home`, `@var`, `@snapshots`
- mounts `/` from `@` with `subvol=@,compress=zstd,noatime`
- mounts `/home` from `@home` with `subvol=@home,compress=zstd`
- mounts `/var` from `@var` with `subvol=@var,compress=zstd,noatime`
- mounts `/.snapshots` from `@snapshots` with `subvol=@snapshots,compress=zstd,noatime`
- writes explicit UUID-based `fstab` entries for all four mount points
- uses matching `rootflags=` in the bootloader entry
- installs `snapper` with timeline and cleanup timers enabled
- `grub-btrfs` is added only on BIOS/GRUB installs (not systemd-boot)

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

Post-install files written to the new user's home directory:

```text
~/archinstall.log          full install log copy
~/archinstall-manifest.txt structured install manifest
```

Useful checks:

```bash
less /tmp/archinstall_install.log
grep -n "\[FAIL\]\|\[WARN\]\|\[DEBUG\]" /tmp/archinstall_install.log
df -h /
df -h /mnt

# After rebooting into the new system:
cat ~/archinstall-manifest.txt
cat ~/archinstall.log
```

The manifest includes hostname, timezone, locale, filesystem, boot mode, disk layout, package list, and environment details.

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
- for SDDM: `systemctl status sddm` and check `/etc/sddm.conf.d/kde_settings.conf`
- for greetd: `systemctl status greetd` and check `/etc/greetd/config.toml`
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
    desktop.sh      Desktop profile helpers (display manager, DM packages)
    hardware.sh     CPU microcode, GPU driver, and VM guest tools detection
    network.sh      Live ISO pacman bootstrap helpers
    packages.sh     Full package strategy resolution and deduplication
    profile.sh      Timezone, locale, and keymap selection helpers
    profiles.sh     Install profile definitions (DAILY, DEV, CUSTOM)
    snapshots.sh    Snapper configuration and snapshot package resolution
    system/
      network.sh    Network package and service helpers
      audio.sh      PipeWire/WirePlumber package and user-unit helpers
      bluetooth.sh  BlueZ package and service helpers
    disk/
      layout.sh     Partition-path helpers
      manager.sh    Disk workflow: wipe, free-space, dual-boot, manual
      space.sh      Target free-space estimation and checks
  state.sh       Shared installer state helpers
  ui.sh          Reusable dialog wrappers
config/
  packages.conf  Package policy: required, base-devel, aur-helper tiers
  system.conf    Compatibility fallback for older callers
plugins/
  example/       Reference plugin showing package + chroot hook pattern
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
