# State

## Source Of Truth

`installer/state.sh` is the single source of truth.

All install decisions must be represented in persisted state before pipeline execution.

## Core Runtime Keys

- `BOOT_MODE`
- `BOOTLOADER`
- `CURRENT_SECURE_BOOT_STATE`
- `CURRENT_SECURE_BOOT_SETUP_MODE`
- `ENVIRONMENT_VENDOR`
- `ENVIRONMENT_TYPE`
- `CPU_VENDOR`
- `GPU_VENDOR`
- `GPU_LABEL`

## Disk Keys

- `DISK`
- `DISK_MODEL`
- `DISK_TRANSPORT`
- `DISK_TYPE`
- `INSTALL_SCENARIO`
- `EFI_PART`
- `ROOT_PART`
- `ROOT_MAPPER`
- `LUKS_PART_UUID`

## Feature Keys

- `FILESYSTEM`
- `ENABLE_LUKS`
- `SNAPSHOT_PROVIDER`
- `ENABLE_ZRAM`
- `INSTALL_STEAM`
- `SECURE_BOOT_MODE`

## Desktop Keys

- `DESKTOP_PROFILE`
- `DISPLAY_MANAGER`
- `GREETER`
- `DISPLAY_SESSION`

## Package Keys

- `INSTALL_PROFILE`
- `EDITOR_CHOICE`
- `INCLUDE_VSCODE`
- `CUSTOM_TOOLS`

## Compatibility

Older compatibility aliases may still be readable from state, but new code must write canonical keys only.
