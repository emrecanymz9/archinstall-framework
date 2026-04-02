# Architecture

## Entry Points

- `installer/install.sh`: dialog and TTY user interface, runtime detection refresh, profile capture, progress UI, install confirmation, final summary.
- `installer/disk.sh`: disk selection entry point and strategy orchestration.
- `installer/executor.sh`: install execution, partition reuse or destructive partitioning, pacstrap, fstab generation, and chroot configuration.

## Shared State

The installer persists UI and install decisions through `installer/core/state.sh`.
`installer/state.sh` remains as a compatibility shim for existing callers.

Important state keys:

- `DISK`, `EFI_PART`, `ROOT_PART`
- `INSTALL_SCENARIO`, `FORMAT_EFI`, `FORMAT_ROOT`
- `BOOT_MODE`, `CURRENT_SECURE_BOOT_STATE`, `CURRENT_SECURE_BOOT_SETUP_MODE`
- `ENVIRONMENT_VENDOR`, `ENVIRONMENT_LABEL`, `GPU_VENDOR`, `GPU_LABEL`, `CPU_VENDOR`
- `INSTALL_PROFILE`, `EDITOR_CHOICE`, `INCLUDE_VSCODE`, `CUSTOM_TOOLS`
- `SECURE_BOOT_MODE`, `DESKTOP_PROFILE`, `DISPLAY_MODE`, `DISPLAY_MANAGER`

## Runtime Awareness

`installer/modules/detect.sh` is the shared detection layer for:

- BIOS vs UEFI
- virtualization platform through `systemd-detect-virt` and DMI data
- environment type classification: `vm`, `laptop`, `desktop`
- GPU vendor fallbacks
- disk model strings and simple OS-presence hints

`installer/modules/system.sh` builds on that shared layer and detects:

- Secure Boot firmware state through EFI variables when available

`installer/modules/hardware.sh` builds on that shared layer and detects:

- guest additions packages and services for VMware, VirtualBox, and QEMU/KVM
- CPU vendor (`intel` / `amd`) to select the correct microcode package
- GPU vendor for mesa, NVIDIA, or generic fallback drivers

The UI refreshes these values at runtime and shows them in:

- the main menu header
- the install menu header
- disk setup header
- live progress view
- state and completion summaries

## Disk Manager

`installer/modules/disk/manager.sh` provides the higher-level disk workflows:

- full disk wipe — partitions 1 GiB EFI + remaining root
- install into free space — requires at least 1 GiB free for EFI + root minimum
- Windows-aware dual-boot free-space flow
- manual partition editing with `cfdisk` or `parted`

Safety checks enforced by the disk manager:

- `validate_existing_efi_partition()`: warns when the selected EFI partition is not vfat, under 512 MiB advisory, or under 256 MiB dangerous
- `check_bios_gpt_safety()`: hard-fails BIOS + GPT installs that lack a `bios_grub` partition; GRUB cannot install without it

The executor only performs destructive repartitioning when `INSTALL_SCENARIO=wipe`.
For other strategies it reuses the prepared partition layout and follows `FORMAT_EFI` and `FORMAT_ROOT`.

## Profiles And Packages

`installer/modules/profiles.sh` defines:

- `daily`
- `dev`
- `custom`

Package policy now loads from `config/packages.conf` first and falls back to `config/system.conf` for compatibility.

`installer/modules/packages.sh` — `resolve_package_strategy()` — merges package sources in order:

1. Required packages from `config/packages.conf` (`ARCHINSTALL_REQUIRED_PACKAGES`)
2. Filesystem packages (`btrfs-progs` for btrfs)
3. Install profile packages (from `profiles.sh`)
4. Hardware packages: CPU microcode (`intel-ucode` / `amd-ucode` from `CPU_VENDOR` state), GPU drivers, VM guest tools
5. Desktop profile packages: Plasma, PipeWire stack, Bluetooth, display manager (`sddm`, `greetd`, etc.)
6. Secure Boot tooling
7. Snapshot packages: `snapper`, `snap-pac`; `grub-btrfs` only when `boot_mode=bios`
8. Optional: `zram-generator`, LUKS2 tools
9. Plugin-contributed packages

Package deduplication happens before `pacstrap`.

## System Modules

Three modules under `installer/modules/system/` provide host-side package and service helpers:

- `network.sh`: `network_required_packages()` returns `(networkmanager iwd)`; `enable_network_services()` enables NetworkManager and iwd on the live host when needed
- `audio.sh`: `audio_required_packages()` returns the PipeWire + WirePlumber stack; `enable_audio_services()` symlinks per-user service units
- `bluetooth.sh`: `bluetooth_required_packages()` returns `(bluez bluez-utils)`; `enable_bluetooth_service()` enables `bluetooth.service` safely

These modules are sourced by `executor.sh` during package strategy resolution.

## Btrfs Layout

When the root filesystem is `btrfs` the executor creates and mounts four subvolumes:

| Subvolume    | Mount point   | Mount options                          |
|--------------|---------------|----------------------------------------|
| `@`          | `/`           | `subvol=@,compress=zstd,noatime`       |
| `@home`      | `/home`       | `subvol=@home,compress=zstd`           |
| `@var`       | `/var`        | `subvol=@var,compress=zstd,noatime`    |
| `@snapshots` | `/.snapshots` | `subvol=@snapshots,compress=zstd,noatime` |

All four entries are written to `/etc/fstab` with UUID-based identifiers.
The bootloader entry receives a matching `rootflags=subvol=@` kernel parameter.

## Snapshot System

`installer/modules/snapshots.sh` — `snapshot_required_packages(provider, filesystem, boot_mode, nameref)` — builds the snapshot package list:

- always adds `snapper` and `snap-pac` when provider is `snapper` and filesystem is `btrfs`
- adds `grub-btrfs` only when `boot_mode=bios` (GRUB installs need it to auto-regenerate snapshot entries; systemd-boot does not)

The chroot script snippet creates a snapper config for `root`, enables `snapper-timeline.timer` and `snapper-cleanup.timer`, and takes an initial snapshot labeled `"base install"`.

## iwd Wi-Fi Backend

When `iwd` is installed in the target system the chroot script automatically:

1. Writes `/etc/NetworkManager/conf.d/wifi_backend.conf` with `wifi.backend=iwd`
2. Enables `iwd.service` via `systemctl enable`

This gives NetworkManager a faster, more reliable Wi-Fi backend on the installed system without requiring manual post-install configuration.

## Display Managers

`installer/modules/desktop.sh` — `select_display_manager()` — offers four choices:

| Key      | Label   | Packages                  | Notes                              |
|----------|---------|---------------------------|------------------------------------|
| `greetd` | greetd  | `greetd tuigreet`         | Default; TUI frontend              |
| `tuigreet` | tuigreet (greetd) | same as greetd | Alias for the greetd+tuigreet pair |
| `qtgreet` | qtgreet | `greetd qtgreet`          | Requires external package source   |
| `sddm`   | SDDM    | `sddm sddm-kcm`           | Recommended for KDE; Qt-based      |

For SDDM the chroot script creates `/etc/sddm.conf.d/kde_settings.conf` with Breeze theme defaults, UID range 1000–60000, and enables `sddm.service`.

## Pacstrap Hardening

`run_pacstrap_install()` in `executor.sh`:

- calls `pacstrap -K /mnt` — the `-K` flag initialises the target pacman keyring before package installation
- the full deduplicated package array is passed as a single expansion; no packages are hardcoded at the call site
- `--noconfirm` is placed after the package list so it applies to package resolution, not to keyring operations

## Install Manifest

After a successful install the executor writes two files to the new user's home directory:

- `archinstall.log` — full copy of `/tmp/archinstall_install.log`
- `archinstall-manifest.txt` — structured summary containing:
  - CONFIGURATION: hostname, timezone, locale, keymap, user, profile, desktop, display manager, filesystem, encryption, snapshots, zram, boot mode, Secure Boot, CPU/GPU/environment vendors
  - DISK LAYOUT: device path, scenario, EFI and root partition details, `lsblk` output, `findmnt /mnt` tree
  - PACKAGES INSTALLED: output of `pacman -Q` from inside the chroot

Both files are created with mode `644` and are readable immediately after the first boot.

## Chroot Configuration

`installer/executor.sh` generates the chroot script dynamically via a bash heredoc with outer delimiter `EOF`. Inner heredocs use named terminators (`LOADERCONF`, `NMCONFIGEOF`, `NMCONF`, `EOT`, `SDDMCONF`) to avoid conflicts. The generated script handles:

- locale, timezone, hostname, and users
- NetworkManager enablement; iwd service enable and NM wifi backend config when `iwctl` is present
- zram configuration
- KDE display-manager setup: greetd/tuigreet, qtgreet, or SDDM with Breeze theme
- virtualization guest services (open-vm-tools, virtualbox-guest-utils, qemu-guest-agent)
- CPU microcode detection for the bootloader `initrd` line
- bootloader install: systemd-boot (UEFI) or GRUB (BIOS, with BIOS+GPT safety check in chroot)
- Secure Boot follow-up note generation and optional `sbctl` key enrollment in firmware setup mode

## UI Model

`installer/ui.sh` is the single UI abstraction layer.

- `dialog` is preferred when available
- TTY fallback is used automatically when dialog fails or is unavailable
- callers read `DIALOG_RESULT` and `DIALOG_STATUS`

That model keeps the installer usable in both normal Arch ISO use and degraded terminal environments.