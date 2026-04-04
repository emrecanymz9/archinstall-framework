# State Model

## Canonical Store

- Persistent installer state lives in `installer/state.sh`.
- Values are normalized on write.
- `installer/core/state.sh` only exists to source the canonical implementation for older callers.

## Core Runtime Keys

- `BOOT_MODE`: `bios|uefi`
- `BOOTLOADER`: `systemd-boot|grub|limine`
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