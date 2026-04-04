# Architecture

## Entry Points

- `installer/install.sh`: interactive configuration, state summaries, confirmation flow, and progress-screen orchestration.
- `installer/disk.sh`: target-disk selection and handoff into the disk strategy module.
- `installer/executor.sh`: package resolution, partitioning or reuse flow, pacstrap, fstab generation, and target chroot configuration.

## Canonical State

- `installer/state.sh` is the single source of truth for persisted installer state.
- `installer/core/state.sh` is only a compatibility shim that sources the canonical implementation.
- Normalization happens when state is written, not ad hoc in each caller.

Phase 4 keys that drive behavior:

- `BOOT_MODE`, `CURRENT_SECURE_BOOT_STATE`, `CURRENT_SECURE_BOOT_SETUP_MODE`, `SECURE_BOOT_MODE`
- `ENVIRONMENT_VENDOR`, `ENVIRONMENT_TYPE`, `CPU_VENDOR`, `GPU_VENDOR`, `GPU_LABEL`
- `DISK`, `DISK_MODEL`, `DISK_TRANSPORT`, `DISK_TYPE`, `INSTALL_SCENARIO`
- `FILESYSTEM`, `ENABLE_LUKS`, `SNAPSHOT_PROVIDER`, `ENABLE_ZRAM`, `INSTALL_STEAM`
- `INSTALL_PROFILE`, `EDITOR_CHOICE`, `INCLUDE_VSCODE`, `CUSTOM_TOOLS`
- `DESKTOP_PROFILE`, `DISPLAY_MANAGER`, `DISPLAY_SESSION`, `GREETER`

Legacy compatibility keys such as `DISPLAY_MODE`, `RESOLVED_DISPLAY_MODE`, and `GREETER_FRONTEND` still mirror the canonical values so older callers do not break.

## Detection Layer

`installer/modules/detect.sh` provides low-level runtime inspection for:

- boot mode
- virtualization vendor and environment type
- CPU and GPU vendors
- disk model, transport bus, and coarse disk type
- network status and simple OS-presence hints on disks

`installer/modules/system.sh` extends that with Secure Boot firmware state and environment labels.
`installer/modules/hardware.sh` turns detection into install decisions such as microcode, guest tools, desktop GPU packages, and optional 32-bit graphics userspace for Steam.

## Package Strategy

`installer/modules/packages.sh` resolves the final pacstrap package set in layers:

1. Base packages from `config/packages.conf`
2. Required profile packages
3. User/profile packages from `installer/modules/profiles.sh`
4. Hardware packages from `installer/modules/hardware.sh`
5. Desktop packages from `installer/modules/desktop.sh`
6. Secure Boot tooling when `SECURE_BOOT_MODE=setup`
7. Snapshot tooling when `SNAPSHOT_PROVIDER=snapper`
8. Optional extras such as zram, LUKS helpers, and Steam
9. Plugin-contributed packages

Package deduplication happens before pacstrap. Steam support also enables the multilib repository on the live ISO and persists that repository into the target system.

## Disk Flow

`installer/modules/disk/manager.sh` owns the strategy workflows:

- full-disk wipe
- GPT initialization for unreadable or blank disks
- free-space install
- Windows-aware dual-boot reuse
- manual partition reuse

`installer/disk.sh` is intentionally thin: it lists disks with model, transport, and disk-type hints, then delegates the selected strategy to the disk manager.

## Display System

Display behavior is deterministic and state-driven:

- `DISPLAY_MANAGER`: `sddm`, `greetd`, or `none`
- `DISPLAY_SESSION`: `wayland` or `x11`
- `GREETER`: `tuigreet`, `qtgreet`, or `none`

Rules:

- KDE defaults to `sddm` with `wayland`
- greetd only uses a greeter when `DISPLAY_MANAGER=greetd`
- non-greetd installs normalize `GREETER=none`
- the chroot script enables exactly one display manager and disables the other

## Filesystem And Snapshots

For `btrfs`, the installer creates `@`, `@home`, `@var`, and `@snapshots` subvolumes and writes matching UUID-based fstab entries.

Snapshots are deterministic:

- `SNAPSHOT_PROVIDER=none` for non-btrfs installs
- `SNAPSHOT_PROVIDER=snapper` only when `FILESYSTEM=btrfs`

When snapper is selected, the chroot phase creates the root config, enables timeline and cleanup timers, and takes an initial snapshot.

## Secure Boot Foundation

`SECURE_BOOT_MODE` is now intentionally minimal:

- `disabled`
- `setup`

`setup` installs `sbctl` and `systemd-ukify`, prepares a UKI path, attempts safe enrollment only when firmware setup mode allows it, and remains non-fatal when firmware ownership or signing cannot be completed during install.

## Generated Chroot Script

`installer/executor.sh` builds the target configuration script as a heredoc. That generated script handles:

- locale, timezone, hostname, users, and sudo
- NetworkManager and iwd setup
- zram and snapper configuration
- KDE service enablement and deterministic display-manager setup
- VM guest services and laptop power services
- UKI and Secure Boot foundation steps
- systemd-boot or GRUB installation

## Operator Artifacts

After a successful install the executor writes:

- `archinstall.log`
- `archinstall-manifest.txt`

The manifest includes runtime detection, disk metadata, display state, Steam flag, snapshot provider, Secure Boot mode, and the installed package list for post-install auditing.

## UI Model

`installer/ui.sh` remains the single UI abstraction. Dialog is preferred, but TTY fallback is first-class and the installer keeps state summaries and confirmations usable in both modes.

That separation keeps the phase-specific logic concentrated in modules instead of burying decisions in the UI layer.

*** Add File: c:\Kanu\archinstall-framework\docs\FEATURES.md
# Features

## Runtime Detection

- Boot mode detection for BIOS and UEFI
- Secure Boot firmware state and setup-mode detection
- Virtualization vendor detection for VMware, VirtualBox, QEMU/KVM, and Hyper-V
- CPU and GPU vendor detection used by package strategy
- Disk model, transport bus, and coarse disk-type reporting in the UI and manifest

## Install Profiles

- `daily`: KDE-first workstation flow with reduced prompts
- `dev`: developer-focused profile with editor and VS Code choices
- `custom`: explicit package, desktop, and optional-feature selection

## Desktop And Login

- KDE Plasma desktop profile
- Deterministic display session selection: `wayland` or `x11`
- Deterministic display manager selection: `sddm`, `greetd`, or `none`
- greetd frontend selection: `tuigreet`, `qtgreet`, or `none`
- Strict enable/disable behavior so only the chosen display manager is active in the target system

## Storage

- Full-disk wipe installs
- GPT initialization for blank or unreadable disks
- Free-space installs
- Windows-aware dual-boot preparation
- Manual partition reuse with EFI validation
- Btrfs subvolume layout: `@`, `@home`, `@var`, `@snapshots`
- Disk-space validation before pacstrap

## Security And Recovery

- Optional LUKS2 root encryption
- Secure Boot foundation mode with `sbctl` and UKI preparation
- Non-fatal Secure Boot workflow for imperfect firmware or VM environments
- Snapper integration for btrfs installs with timeline and cleanup timers
- BIOS plus GPT safety checks before GRUB install

## Package Strategy

- Config-driven base and required package sets from `config/packages.conf`
- GPU-aware driver selection for Intel, AMD, NVIDIA, and virtualized systems
- CPU microcode package selection
- Guest tools for supported hypervisors
- Optional Steam support with multilib enablement and 32-bit graphics userspace
- Optional zram and VS Code support
- Plugin-contributed packages merged into the final pacstrap set

## UX And Operations

- Dialog-first UI with TTY fallback
- Live progress output with recent log lines
- Saved installer state summaries
- Install manifest and copied install log in the target user home directory

*** Add File: c:\Kanu\archinstall-framework\docs\STATE.md
# State Model

## Canonical Store

- Persistent installer state lives in `installer/state.sh`.
- Values are normalized on write.
- `installer/core/state.sh` only exists to source the canonical implementation for older callers.

## Core Runtime Keys

- `BOOT_MODE`: `bios|uefi`
- `CURRENT_SECURE_BOOT_STATE`: `enabled|disabled|unsupported|unknown`
- `CURRENT_SECURE_BOOT_SETUP_MODE`: `setup|user|unknown`
- `ENVIRONMENT_VENDOR`: `baremetal|vmware|virtualbox|kvm|qemu|hyperv|unknown`
- `ENVIRONMENT_TYPE`: `desktop|laptop|vm|unknown`
- `CPU_VENDOR`: `intel|amd|unknown`
- `GPU_VENDOR`: `intel|amd|nvidia|generic|vm`
- `GPU_LABEL`: human-readable label derived from `GPU_VENDOR`

## Disk Keys

- `DISK`: selected install target block device
- `DISK_MODEL`: descriptive model string from lsblk or sysfs
- `DISK_TRANSPORT`: `nvme|sata|ata|usb|scsi|virtio|emmc|unknown`
- `DISK_TYPE`: normalized physical class `nvme|ssd|hdd|unknown`
- `INSTALL_SCENARIO`: `wipe|initialize|free-space|dual-boot|manual`
- `EFI_PART`, `ROOT_PART`, `ROOT_MAPPER`, `LUKS_PART_UUID`

## Feature Keys

- `FILESYSTEM`: `ext4|btrfs`
- `ENABLE_LUKS`: boolean string
- `SNAPSHOT_PROVIDER`: `none|snapper`
- `ENABLE_ZRAM`: boolean string
- `INSTALL_STEAM`: boolean string
- `SECURE_BOOT_MODE`: `disabled|setup`

## Profile And Package Keys

- `INSTALL_PROFILE`: `daily|dev|custom`
- `EDITOR_CHOICE`: `nano|micro|vim|kate`
- `INCLUDE_VSCODE`: boolean string
- `CUSTOM_TOOLS`: space-separated extra package list

## Desktop Keys

- `DESKTOP_PROFILE`: currently `kde|none`
- `DISPLAY_MANAGER`: `sddm|greetd|none`
- `DISPLAY_SESSION`: `wayland|x11`
- `GREETER`: `tuigreet|qtgreet|none`

## Compatibility Keys

These still exist for older callers and exported summaries, but canonical behavior is driven by the keys above:

- `DISPLAY_MODE`
- `RESOLVED_DISPLAY_MODE`
- `GREETER_FRONTEND`

They mirror normalized display state and should not be treated as the source of truth for new code.