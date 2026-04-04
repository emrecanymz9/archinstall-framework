# Architecture

## Entry Points

- `installer/install.sh`: interactive UI, state capture, validation, and confirmations.
- `installer/executor.sh`: orchestration entrypoint.
- `installer/state.sh`: single source of truth for persisted installer state.

## Canonical Structure

- `installer/core/`: shared hooks, registries, and pipeline execution.
- `installer/modules/`: execution helpers only.
- `installer/features/`: decision logic only.
- `installer/boot/`: bootloader-specific snippets only.
- `installer/postinstall/`: finalization, services, logs, and cleanup.

## Runtime Rules

- Runtime and hardware detection are refreshed into state before the install pipeline runs.
- The executor consumes persisted state; it does not make user-intent decisions.
- Disk metadata is persisted as `DISK_MODEL`, `DISK_TYPE`, and `DISK_TRANSPORT`.
- Display state is persisted as `DISPLAY_MANAGER`, `GREETER`, and `DISPLAY_SESSION`.

## Pipeline

The final install pipeline is:

1. `apply_disk`
2. `apply_base`
3. `apply_gpu`
4. `apply_display`
5. `apply_boot`
6. `apply_features`
7. `apply_postinstall`

## Package Resolution

Package resolution is deterministic and driven by explicit inputs plus persisted state.

Always-installed packages include:

- `base`
- `linux`
- `linux-firmware`
- `mkinitcpio`
- `sudo`
- `networkmanager`
- `iwd`
- `iptables-nft`
- `dialog`
- `make`
- `nano`
- `git`
- `curl`
- `wget`
- `ripgrep`
- `fd`
- `less`
- `man-db`
- `man-pages`

Optional checklist packages are limited to:

- `firefox`
- `keepassxc`
- `vscode`
- `fastfetch`

## Display System

Decision layer:

- `installer/features/display.sh`

Execution layer:

- `installer/modules/display/manager.sh`

Allowed values:

- `DISPLAY_MANAGER`: `sddm|greetd|none`
- `GREETER`: `tuigreet|qtgreet|none`
- `DISPLAY_SESSION`: `wayland|x11`

`postinstall/services.sh` is the only place that enables or disables display-manager services and it always sets `graphical.target`.

## Boot System

All boot logic lives under:

- `installer/boot/systemd-boot.sh`
- `installer/boot/grub.sh`
- `installer/boot/limine.sh`

The executor injects the selected boot snippet; it does not call bootloader installers directly.

## Postinstall

- `installer/postinstall/finalize.sh`: locale, hostname, users, sudo, mkinitcpio.
- `installer/postinstall/services.sh`: all service enablement and display-manager exclusivity.
- `installer/postinstall/logs.sh`: export install logs to `/var/log/archinstall.log` and `/home/$USER/install.log`.
- `installer/postinstall/cleanup.sh`: cleanup steps.
