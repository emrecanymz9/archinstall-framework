# Architecture

## Entry Points

- `installer/install.sh`: staged TUI flow, state capture, validation, and confirmation.
- `installer/executor.sh`: install orchestration and chroot handoff.
- `installer/state.sh`: canonical persisted state store.

## Canonical Structure

- `installer/core/`: runtime execution, package resolution, disk helpers, runtime detection, and orchestrated system mutation.
- `installer/ui/`: dialog wrappers only. No system mutation belongs here.
- `installer/validation/`: input validation and state-gating helpers.
- `installer/features/`: decision logic only.
- `installer/boot/`: bootloader abstraction, capability rules, and bootloader-specific snippets.
- `installer/postinstall/`: finalization, display-manager configuration, service enablement, log export, and cleanup.

The ambiguous `installer/modules/` directory was removed. Runtime helpers now live under `installer/core/`, dialog code under `installer/ui/`, and input validation under `installer/validation/`.

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

- Execution flow is now explicit: `ui -> validation -> core -> postinstall`.
- Runtime and hardware detection refresh into state before the pipeline runs.
- The executor consumes persisted state and does not invent user intent.
- UI code must not run system mutation commands.
- Disk metadata persists as `DISK_MODEL`, `DISK_TRANSPORT`, and `DISK_TYPE`.
- `DISK_TYPE` is normalized to `hdd|ssd|nvme|vm`.
- Display state persists as `DISPLAY_MANAGER`, `GREETER`, and `DISPLAY_SESSION`.
- Chroot runtime values must be materialized from state into `/mnt/root/.install_env` before `arch-chroot` runs.

## Environment Injection Layer

The executor owns chroot environment preparation.

Separation of responsibility:

- state: `installer/state.sh` persists the canonical install decisions
- execution: `installer/executor.sh` validates required runtime values and starts `arch-chroot`
- environment: `installer/executor.sh` writes `/mnt/root/.install_env` from validated state for chroot consumers

Mandatory rule:

All variables used inside chroot MUST be passed via `/root/.install_env` and sourced at runtime. Direct variable interpolation inside heredoc (for example, `arch-chroot /mnt <<EOF`) is FORBIDDEN.

Why this rule exists:

- heredoc interpolation can expand on the host side instead of in the target system
- escaped variables can survive into chroot as literal strings and fail silently
- silent expansion bugs break deterministic installs and are hard to audit
- direct interpolation bypasses the explicit state-to-execution boundary

Execution flow:

```text
executor -> writes /mnt/root/.install_env
         -> arch-chroot
         -> chroot scripts source /root/.install_env
         -> postinstall logic executes
```

Required pattern:

```bash
# inside chroot runtime
source /root/.install_env
echo "$TARGET_LOCALE"
```

Forbidden pattern:

```bash
arch-chroot /mnt <<EOF
echo "$TARGET_LOCALE"
EOF
```

## Pipeline

The install pipeline remains ordered and explicit:

1. `apply_disk`
2. `apply_base`
3. `apply_gpu`
4. `apply_display`
5. `apply_boot`
6. `apply_features`
7. `apply_postinstall`

The runtime handoff is layered:

1. UI collects input
2. validation normalizes and rejects bad state
3. core applies disk, package, and runtime execution
4. postinstall performs chroot-only mutation

## Package Resolution

Package resolution is deterministic and split into two phases:

1. Mandatory core pacstrap packages: `base`, `linux`, `linux-firmware`, `mkinitcpio`, `sudo`, `networkmanager`
2. Optional package layers resolved from filesystem, profile, hardware, desktop, features, and custom selections

Only optional packages are validated before install. Core packages are never skipped.

## Display System

Decision layer:

- `installer/features/display.sh`

Execution layer:

- `installer/postinstall/display-manager.sh`

Allowed values:

- `DISPLAY_MANAGER`: `sddm|greetd|none`
- `GREETER`: `tuigreet|qtgreet|none`
- `DISPLAY_SESSION`: `wayland|x11`

`postinstall/services.sh` is the only place that enables or disables display-manager services, and it always enforces a single graphical target strategy.

Current greetd flow:

- `postinstall/display-manager.sh` writes `/etc/greetd/config.toml`
- greetd sessions run through `/usr/local/bin/archinstall-start-session`
- Wayland uses `dbus-run-session startplasma-wayland`
- X11 uses `dbus-run-session startplasma-x11`
- `postinstall/services.sh` validates the greetd config before enabling `greetd.service`
- greetd failures are logged to `/var/log/greetd-boot.log`

## Boot System

All boot logic lives under:

- `installer/boot/systemd-boot.sh`
- `installer/boot/grub.sh`
- `installer/boot/limine.sh`

The boot system is capability-based rather than hardcoded.

Bootloader capabilities are evaluated against:

- firmware mode
- Secure Boot mode
- LUKS usage
- user-selected experience level

Operational guidance:

- `systemd-boot`: recommended for UEFI and the primary Secure Boot foundation path
- `GRUB`: advanced but broadly compatible, especially for BIOS
- `Limine`: advanced and experimental for Secure Boot use cases

The executor injects the selected boot snippet; it does not scatter bootloader install logic through unrelated modules.

## Password System

Password application is part of postinstall, not UI.

Execution order inside chroot:

1. create the primary user
2. normalize `/etc/shadow` ownership and mode
3. apply root password
4. apply user password

Application rules:

- non-empty passwords use `chpasswd`
- empty passwords use `passwd -d`
- failed password operations abort the install
- password operations log before execution, after execution, and on failure

Failure scenarios addressed by the current implementation:

- missing or invalid chroot state
- bad `/etc/shadow` ownership or mode
- password application attempted before user creation
- late chpasswd failures that would otherwise leave the system half-configured

## Postinstall

- `installer/postinstall/finalize.sh`: locale, hostname, `/etc/shadow`, users, passwords, sudo, mkinitcpio.
- `installer/postinstall/display-manager.sh`: chroot display-manager configuration.
- `installer/postinstall/services.sh`: service enablement and display-manager exclusivity.
- `installer/postinstall/logs.sh`: export the install log to `/var/log/archinstall.log` and `/home/$USER/install.log`.
- `installer/postinstall/cleanup.sh`: cleanup steps.

All postinstall scripts must treat `/root/.install_env` as the chroot runtime contract. They must not depend on host-side heredoc variable injection.
