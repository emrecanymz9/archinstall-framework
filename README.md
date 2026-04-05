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

The installer is interactive. Start it, then move through the staged flow.

Profile selection now happens in `Desktop`, and identity plus optional package choices happen in `Packages`.

- `DAILY`: full workstation defaults with KDE and common tools
- `DEV`: development-oriented toolset with a leaner package set
- `CUSTOM`: choose editor, VS Code, tools, desktop, and display behavior manually

Example launch for a `DAILY` install:

```bash
cd archinstall-framework
bash installer/install.sh
```

Then open `Desktop`, choose `DAILY`, review `Display manager`, then finish `Packages` and `Summary`.

Example launch for a `DEV` install:

```bash
cd archinstall-framework
bash installer/install.sh
```

Then open `Desktop`, choose `DEV`, review `Display manager`, then finish `Packages` and `Summary`.

### One-Line Curl Installer

This downloads the repository archive, extracts it, and launches the installer:

```bash
curl -fsSL https://github.com/emrecanymz9/archinstall-framework/archive/refs/heads/main.tar.gz | tar -xz && cd archinstall-framework-main && bash installer/install.sh
```

The installer intentionally keeps the live ISO minimal. Heavy packages belong in the target system through `pacstrap`, not in the RAM-backed ISO environment.

## Features

- staged install flow: `Disk -> Partition -> Desktop -> Display manager -> Packages -> Summary -> Install`
- runtime-aware UI with boot-mode, Secure Boot, and environment detection
- ext4 and btrfs root installs
- disk typing for `NVMe SSD`, `SATA SSD`, `HDD`, and `VM Disk`
- disk-space validation on `/mnt` before `pacstrap`
- disk manager with full-wipe, free-space, dual-boot, initialize, and manual strategies
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
- display managers: `greetd` with `tuigreet` or optional `qtgreet`, or `sddm` (recommended for KDE)
- btrfs four-subvolume layout: `@`, `@home`, `@var`, `@snapshots`
- snapper timeline snapshots with automatic cleanup timers
- `grub-btrfs` included only for BIOS/GRUB installs
- Secure Boot foundation mode for UKI + `sbctl` preparation without making install success depend on signing
- 1 GiB EFI partition enforced on new wipe/free-space installs
- EFI validation on manual partition reuse (size and filesystem warnings)
- BIOS + GPT safety check blocks unsafe grub-install scenarios
- mandatory core pacstrap packages are always installed and never skipped
- optional packages are validated only after the core bootstrap phase
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

Compatibility wrappers are no longer part of the active target architecture. New code should only use the canonical directories above.

Additional documentation:

- `docs/architecture.md`
- `docs/chroot.md`
- `docs/features.md`
- `docs/state.md`
- `docs/roadmap.md`

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

## Chroot Safety Rules

All variables used inside chroot MUST be passed via `/root/.install_env` and sourced at runtime. Direct variable interpolation inside heredoc (for example, `arch-chroot /mnt <<EOF`) is FORBIDDEN.

Rules:

- executor writes `/mnt/root/.install_env` from validated installer state before chroot execution
- chroot logic must begin by sourcing `/root/.install_env`
- chroot snippets must consume runtime values from the sourced environment, not from host-side heredoc interpolation
- empty locale or username values must fail before chroot and must fail again inside chroot if missing

Why this is mandatory:

- heredoc interpolation is fragile and can silently turn runtime variables into literal strings
- escaped variables such as `\$TARGET_LOCALE` break locale and user configuration determinism
- implicit host-side expansion violates the state-driven execution model
- environment injection keeps state, execution, and validation responsibilities separated

## Install Flow

1. Open `Disk` and choose the target device.
2. Open `Partition` and choose the filesystem, encryption, snapshots, zram, Secure Boot mode, and partition strategy.
3. Open `Desktop` and choose the install profile, desktop, and Steam preference.
4. Open `Display manager` and choose the session, display manager, and greeter.
5. Open `Packages` and set hostname, timezone, locale, keyboard, users, editor, and optional apps.
6. Open `Summary` and review the saved state.
7. Start `Install`.

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

Pacstrap is split into two phases.

Core packages are always installed first and are never validated away:

- `base`
- `linux`
- `linux-firmware`
- `mkinitcpio`
- `sudo`
- `networkmanager`

Optional packages are resolved and validated after the core bootstrap phase.

Optional layers include:

1. required system tools from `config/packages.conf`
2. filesystem packages such as `btrfs-progs`
3. profile packages from `DAILY`, `DEV`, or `CUSTOM`
4. hardware packages such as CPU microcode, GPU drivers, and VM guest tools
5. desktop packages such as Plasma, PipeWire, Bluetooth, and the selected display manager
6. feature packages for snapshots, Steam, zram, encryption, and Secure Boot foundation mode
7. plugin-contributed packages

## Post-Install Pipeline

After pacstrap, the installer runs a structured post-install phase inside the chroot:

1. `finalize.sh` applies hostname, locale, timezone, sudo, and user configuration.
2. `services.sh` enables NetworkManager, iwd, the selected display manager, and snapper timers when needed.
3. the selected bootloader is installed.
4. Secure Boot setup runs when requested.
5. host-side log export writes `/var/log/archinstall.log` and `/home/$USER/install.log` into the target.
6. `cleanup.sh` removes installer temp files from the target.

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

Post-install files written into the target system:

```text
/var/log/archinstall.log   full install log copy
/home/$USER/install.log    user-readable install log copy
~/archinstall-manifest.txt structured install manifest
```

Useful checks:

```bash
less /tmp/archinstall_install.log
grep -n "\[FAIL\]\|\[WARN\]\|\[DEBUG\]" /tmp/archinstall_install.log
df -h /
df -h /mnt

# After rebooting into the new system:
cat /var/log/archinstall.log
cat ~/install.log
cat ~/archinstall-manifest.txt
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
- choose `Wayland` or `X11` explicitly on the `Display manager` screen
- invalid display values are rejected instead of being auto-corrected during apply

## Layout

```text
installer/
  install.sh      Staged installer UI entry point
  executor.sh     Install core and chroot configuration
  disk.sh         Disk discovery, disk selection, and partition strategy entrypoints
  core/           Pipeline, hooks, and registries
  modules/        Package, hardware, and execution helpers
  features/       Decision logic for display, Secure Boot, snapshots, and Steam
  boot/           systemd-boot, GRUB, and Limine snippets
  postinstall/    Finalize, services, logs, and cleanup
  state.sh        Shared installer state helpers
  ui.sh           Reusable dialog wrappers
config/
  packages.conf  Package policy for core, required, and optional layers
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
