# State

## Source Of Truth

`installer/state.sh` is the single source of truth.

Every install decision must exist in persisted state before the pipeline starts.

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

`DISK_TYPE` is canonicalized to one of:

- `hdd`
- `ssd`
- `nvme`
- `vm`

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
- `CUSTOM_CHECKLIST`
- `CUSTOM_EXTRA`

## State Rules

- Disk selection and partition strategy are separate states.
- Guided partitioning must write `INSTALL_SCENARIO` before installation can begin.
- Display values must remain explicit; invalid values should be rejected rather than auto-corrected during apply.
- New code should only read and write canonical keys.
- Chroot execution must derive runtime variables from persisted state through `/root/.install_env`; the environment file is a runtime projection, not a second source of truth.
- Required values such as locale and username must be validated before chroot handoff.
