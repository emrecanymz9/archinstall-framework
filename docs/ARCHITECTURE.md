# Architecture

## Entry Points

- `installer/install.sh`: dialog and TTY user interface, runtime detection refresh, profile capture, progress UI, install confirmation, final summary.
- `installer/disk.sh`: disk selection entry point and strategy orchestration.
- `installer/executor.sh`: install execution, partition reuse or destructive partitioning, pacstrap, fstab generation, and chroot configuration.

## Shared State

The installer persists UI and install decisions through `installer/state.sh`.

Important state keys:

- `DISK`, `EFI_PART`, `ROOT_PART`
- `INSTALL_SCENARIO`, `FORMAT_EFI`, `FORMAT_ROOT`
- `BOOT_MODE`, `CURRENT_SECURE_BOOT_STATE`, `CURRENT_SECURE_BOOT_SETUP_MODE`
- `ENVIRONMENT_VENDOR`, `ENVIRONMENT_LABEL`, `GPU_VENDOR`, `GPU_LABEL`
- `INSTALL_PROFILE`, `EDITOR_CHOICE`, `INCLUDE_VSCODE`, `CUSTOM_TOOLS`
- `SECURE_BOOT_MODE`, `DESKTOP_PROFILE`, `DISPLAY_MODE`, `DISPLAY_MANAGER`

## Runtime Awareness

`installer/modules/system.sh` detects:

- BIOS vs UEFI
- Secure Boot firmware state through EFI variables when available
- virtualization platform through `systemd-detect-virt` and DMI data

`installer/modules/hardware.sh` detects:

- GPU vendor through `lspci`
- guest additions packages and services for VMware, VirtualBox, and QEMU/KVM

The UI refreshes these values at runtime and shows them in:

- the main menu header
- the install menu header
- disk setup header
- live progress view
- state and completion summaries

## Disk Manager

`installer/modules/disk/manager.sh` provides the higher-level disk workflows:

- full disk wipe
- install into free space
- Windows-aware dual-boot free-space flow
- manual partition editing with `cfdisk` or `parted`

The executor only performs destructive repartitioning when `INSTALL_SCENARIO=wipe`.
For other strategies it reuses the prepared partition layout and follows `FORMAT_EFI` and `FORMAT_ROOT`.

## Profiles And Packages

`installer/modules/profiles.sh` defines:

- `daily`
- `dev`
- `custom`

`installer/executor.sh` merges package sources from:

- base install requirements
- filesystem requirements
- install profile packages
- hardware packages
- Secure Boot tooling packages
- desktop profile packages

Package deduplication happens before `pacstrap`.

## Chroot Configuration

`installer/executor.sh` generates the chroot script dynamically. The generated script handles:

- locale, timezone, hostname, and users
- NetworkManager enablement
- zram configuration
- KDE display-manager setup
- virtualization guest services
- bootloader install
- Secure Boot follow-up note generation and optional `sbctl` key enrollment in firmware setup mode

## UI Model

`installer/ui.sh` is the single UI abstraction layer.

- `dialog` is preferred when available
- TTY fallback is used automatically when dialog fails or is unavailable
- callers read `DIALOG_RESULT` and `DIALOG_STATUS`

That model keeps the installer usable in both normal Arch ISO use and degraded terminal environments.