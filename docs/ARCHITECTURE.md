# Architecture

## Entry Points

- `installer/install.sh`: interactive configuration and operator-facing summaries.
- `installer/executor.sh`: install orchestration, pacstrap, fstab handoff, and chroot execution.
- `installer/state.sh`: canonical persisted state implementation.

## Canonical Layout

The installer now treats these directories as the stable structure:

- `installer/core/`: shared registries, hooks, plugin loading, and compatibility shims.
- `installer/modules/`: runtime, disk, display, GPU, network, and system-oriented helpers.
- `installer/features/`: optional feature units such as Steam, snapshots, and Secure Boot.
- `installer/boot/`: bootloader helpers and bootloader-specific chroot snippets.
- `installer/postinstall/`: finalization, service enablement, and cleanup snippets.

Legacy module paths still exist where needed as wrappers so existing imports do not break while the new folders become the canonical structure.

## State Model

State is normalized at write time in `installer/state.sh`.

Primary keys for install orchestration:

- `BOOT_MODE`, `BOOTLOADER`
- `CURRENT_SECURE_BOOT_STATE`, `CURRENT_SECURE_BOOT_SETUP_MODE`, `SECURE_BOOT_MODE`
- `DISK`, `DISK_MODEL`, `DISK_TRANSPORT`, `DISK_TYPE`, `INSTALL_SCENARIO`
- `FILESYSTEM`, `ENABLE_LUKS`, `SNAPSHOT_PROVIDER`, `ENABLE_ZRAM`, `INSTALL_STEAM`
- `INSTALL_PROFILE`, `EDITOR_CHOICE`, `INCLUDE_VSCODE`, `CUSTOM_TOOLS`
- `DESKTOP_PROFILE`, `DISPLAY_MANAGER`, `DISPLAY_SESSION`, `GREETER`
- `ENVIRONMENT_VENDOR`, `ENVIRONMENT_TYPE`, `CPU_VENDOR`, `GPU_VENDOR`

Compatibility aliases such as `DISPLAY_MODE`, `RESOLVED_DISPLAY_MODE`, and `GREETER_FRONTEND` remain mirrored for older callers.

## Detection And Modules

`installer/modules/detect.sh` remains the low-level probe layer for boot mode, virtualization, CPU/GPU vendors, disk metadata, and network hints.

The higher-level module split is now:

- `installer/modules/disk/`: partition strategy and disk analysis.
- `installer/modules/display/`: compatibility entrypoints for display-manager logic.
- `installer/modules/gpu/`: compatibility entrypoints for GPU package logic.
- `installer/modules/network/`: compatibility entrypoints for network helpers.
- `installer/modules/system/`: runtime and host-system state helpers.

## Package Resolution

`installer/modules/packages.sh` resolves the pacstrap set in deterministic layers:

1. base packages
2. required profile packages
3. profile and user packages
4. hardware packages
5. bootloader packages
6. desktop packages
7. Secure Boot tooling
8. snapshot tooling
9. optional feature packages such as Steam and zram
10. plugin-contributed packages

Bootloader package selection is now explicit through `BOOTLOADER`, which supports `systemd-boot`, `grub`, and `limine`.

## Boot Pipeline

Bootloader installation is now delegated to `installer/boot/`.

- `installer/boot/systemd-boot.sh`
- `installer/boot/grub.sh`
- `installer/boot/limine.sh`

The executor still builds one chroot script, but it now injects the selected bootloader snippet instead of hardcoding bootloader installation inline. Only one bootloader path is executed for a given install.

Limine support is integrated for both BIOS and UEFI at a basic deterministic level:

- installs `limine`
- writes `/boot/limine.cfg`
- uses the same kernel command-line builder as GRUB and systemd-boot
- supports LUKS and btrfs through the shared root command-line logic

## Feature Pipeline

Optional feature behavior is delegated to `installer/features/`:

- `secureboot.sh`: state labels, package selection, and setup-mode semantics.
- `snapshots.sh`: snapper package logic and btrfs snapshot setup.
- `steam.sh`: multilib preparation and target persistence for Steam installs.

This keeps feature-specific decisions out of the main executor flow.

## Post-Install Pipeline

Post-install work is now structured under `installer/postinstall/`.

- `finalize.sh`: locale, timezone, hostname, sudo, user provisioning, and the host-side fstab wrapper.
- `enable_services.sh`: NetworkManager, iwd, selected display manager, and snapper timers.
- `cleanup.sh`: final temp-file cleanup in the target system.

The executor calls these snippets after package installation, inside the chroot, before the install returns control to the operator.

## Chroot Flow

The generated chroot script now proceeds in this order:

1. finalize base system state
2. define service helpers
3. install or repair optional packages as needed
4. apply feature snippets
5. configure desktop and display assets
6. run VM helper enablement
7. run structured post-install service enablement
8. install exactly one bootloader
9. apply Secure Boot setup if requested
10. perform cleanup

## Operator Artifacts

After a successful install the executor still writes:

- `archinstall.log`
- `archinstall-manifest.txt`

The manifest now records bootloader choice alongside runtime, disk, filesystem, display, and feature state.