# Architecture

## Entry Points

- `installer/install.sh`: staged TUI flow, state capture, validation, and confirmation.
- `installer/executor.sh`: install orchestration and chroot handoff.
- `installer/state.sh`: canonical persisted state store.

## Canonical Structure

- `installer/core/`: hooks, registries, and pipeline execution.
- `installer/modules/`: execution helpers and package composition.
- `installer/features/`: decision logic only.
- `installer/boot/`: bootloader-specific snippets.
- `installer/postinstall/`: finalization, service enablement, log export, and cleanup.

Unused compatibility wrappers were removed from the active architecture. New code should only depend on the canonical paths above.

## UI Flow

The interactive installer now follows a fixed staged flow:

1. `Disk`
2. `Partition`
3. `Desktop`
4. `Display manager`
5. `Packages`
6. `Summary`
7. `Install`

The `Disk` step only selects the device. The `Partition` step is the only place that chooses wipe, free-space, dual-boot, initialize, or manual reuse.

## Runtime Rules

- Runtime and hardware detection refresh into state before the pipeline runs.
- The executor consumes persisted state and does not invent user intent.
- Disk metadata persists as `DISK_MODEL`, `DISK_TRANSPORT`, and `DISK_TYPE`.
- `DISK_TYPE` is normalized to `hdd|ssd|nvme|vm`.
- Display state persists as `DISPLAY_MANAGER`, `GREETER`, and `DISPLAY_SESSION`.

## Pipeline

The install pipeline remains ordered and explicit:

1. `apply_disk`
2. `apply_base`
3. `apply_gpu`
4. `apply_display`
5. `apply_boot`
6. `apply_features`
7. `apply_postinstall`

## Package Resolution

Package resolution is deterministic and split into two phases:

1. Mandatory core pacstrap packages: `base`, `linux`, `linux-firmware`, `mkinitcpio`, `sudo`, `networkmanager`
2. Optional package layers resolved from filesystem, profile, hardware, desktop, features, and custom selections

Only optional packages are validated before install. Core packages are never skipped.

## Display System

Decision layer:

- `installer/features/display.sh`

Execution layer:

- `installer/modules/display/manager.sh`

Allowed values:

- `DISPLAY_MANAGER`: `sddm|greetd|none`
- `GREETER`: `tuigreet|qtgreet|none`
- `DISPLAY_SESSION`: `wayland|x11`

`postinstall/services.sh` is the only place that enables or disables display-manager services, and it always enforces a single graphical target strategy.

## Boot System

All boot logic lives under:

- `installer/boot/systemd-boot.sh`
- `installer/boot/grub.sh`
- `installer/boot/limine.sh`

The executor injects the selected boot snippet; it does not scatter bootloader install logic through unrelated modules.

## Postinstall

- `installer/postinstall/finalize.sh`: locale, hostname, users, sudo, mkinitcpio.
- `installer/postinstall/services.sh`: service enablement and display-manager exclusivity.
- `installer/postinstall/logs.sh`: export the install log to `/var/log/archinstall.log` and `/home/$USER/install.log`.
- `installer/postinstall/cleanup.sh`: cleanup steps.
