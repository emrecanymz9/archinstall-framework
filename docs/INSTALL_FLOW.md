# Install Flow

## Overview

The installer is split into two layers:

- [installer/install.sh](../installer/install.sh): dialog-driven UI, state capture, validation, and confirmations
- [installer/executor.sh](../installer/executor.sh): partitioning, pacstrap, chroot configuration, bootloader setup, and final logging

State is persisted in `/tmp/archinstall_state` through [installer/state.sh](../installer/state.sh).

## Runtime Sequence

1. Startup loads optional modules through guarded sourcing.
2. Runtime context is refreshed:
   - boot mode
   - Secure Boot state
   - virtualization vendor
   - GPU vendor
3. The operator chooses a disk strategy:
   - wipe
   - initialize
   - free-space
   - dual-boot
   - manual
4. The operator configures the install profile.
5. The installer runs in safe mode by default and shows a final summary.
6. The operator must type `YES` for destructive operations and for the final install launch.
7. The executor performs the install.

## Package Resolution

Package selection is config-driven.

Source of truth:

- [config/system.conf](../config/system.conf)

Resolution tiers:

- base: hidden packages such as `base`, `linux`, `linux-firmware`, and `mkinitcpio`
- required: semi-hidden platform packages such as `sudo`, `networkmanager`, and `dialog`
- user: visible profile and tool packages

The profile module exposes `get_final_packages()` to merge those tiers before the executor adds:

- filesystem-specific packages
- bootloader packages
- desktop packages
- hardware packages
- Secure Boot packages
- plugin packages

Duplicates are removed before `pacstrap` runs.

## Disk Flow

Disk planning happens before the executor starts destructive work.

Disk classification distinguishes:

- ready partition tables
- empty new disks with no partition table
- damaged or unreadable layouts that should be initialized first

The preview screen shows:

- partitions to create or reuse
- target filesystems
- mount points
- btrfs subvolume plan when applicable
- bootloader path
- Secure Boot/UKI preparation when enabled

Free-space partition creation requires typed `YES` before changes are applied.
Full-disk wipe and disk initialization also require typed `YES`.
The final install launch also requires typed `YES`.

## Chroot Flow

Inside the target system the executor configures:

- locale, timezone, hostname, and keymap
- user and root credentials
- sudo
- NetworkManager
- desktop services when selected
- bootloader
- Secure Boot and UKI workflow when enabled

For UEFI installs with Secure Boot enabled, the chroot path:

- writes `/etc/kernel/cmdline`
- prepares mkinitcpio UKI presets
- uses `mkinitcpio` with `ukify`
- signs generated EFI binaries with `sbctl` when possible

Failures in optional Secure Boot steps are warnings, not fatal install errors.

## Hooks

Plugin hooks can run at these points:

- `pre_disk`
- `post_disk`
- `pre_install`
- `post_chroot`
- `post_install`

Plugins can also inject chroot snippets and menu entries. See [docs/PLUGINS.md](PLUGINS.md).