# Disk Manager

## Goals

The disk manager is designed to avoid unconditional data loss.

It inspects disks with `lsblk`, `blkid`, and `parted` and exposes four install strategies:

- `wipe`: recreate the partition table during install
- `free-space`: create Linux partitions inside the largest free-space region
- `dual-boot`: same as free-space, but explicitly warns when Windows signatures are detected
- `manual`: open a partition editor and then let the user choose root and EFI partitions

## Disk Discovery

The disk list shows:

- device path
- model
- size in GiB
- label when present
- OS warnings
- current partition summary

The Arch ISO boot device is excluded automatically.

## Detection Rules

Windows warnings are based on NTFS and Microsoft-style partition labels.

Linux warnings are based on common Linux filesystems and Linux-style partition labels.

This is advisory data intended to improve operator awareness before destructive actions.

## Free-Space And Dual-Boot Flow

The free-space workflow:

1. finds the largest free region with `parted ... print free`
2. calculates the required root size from the selected desktop profile and filesystem
3. reuses an existing EFI partition when available on UEFI systems
4. creates a new EFI partition only when UEFI is required and no reusable EFI partition exists
5. saves the resulting `EFI_PART`, `ROOT_PART`, `FORMAT_EFI`, and `FORMAT_ROOT` state for the executor

The executor then mounts and installs onto those partitions without wiping the whole disk.

## Manual Editing

The manual workflow launches:

- `cfdisk` when available
- otherwise `parted`

After the editor closes, the installer asks the user to select:

- the root partition
- the EFI partition on UEFI systems
- whether the EFI partition should be formatted

The selected root partition is always treated as the install target filesystem and is formatted during install.

## Safety Boundaries

What the current implementation does safely:

- detect Windows and Linux layouts
- preserve existing EFI partitions when requested
- avoid full-disk wipe for free-space, dual-boot, and manual strategies
- require explicit confirmation before destructive full-disk reuse

What the current implementation intentionally leaves to the manual editor:

- shrinking existing filesystems
- resizing Windows partitions
- complex partition moves

Those operations are too filesystem-specific to automate safely in a generic Bash installer without stronger validation.