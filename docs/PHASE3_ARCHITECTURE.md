# Phase 3 Architecture

Phase 3 moves the installer toward a production-grade layered design while preserving the working Bash-based execution flow.

## Layers

### UI Layer

- `installer/install.sh`
- `installer/ui.sh`
- `installer/disk.sh`

Responsibilities:

- collect user input
- render dialog and TTY fallback flows
- persist install choices into shared state
- synchronize the JSON config object

### Logic Layer

- `installer/modules/config.sh`
- `installer/modules/packages.sh`
- `installer/modules/hardware.sh`
- `installer/modules/detect.sh`
- `installer/modules/luks.sh`
- `installer/modules/snapshots.sh`
- `installer/modules/disk/manager.sh`
- `installer/modules/desktop.sh`
- `installer/modules/bootloader.sh`
- `installer/modules/network.sh`

Responsibilities:

- normalize runtime and hardware data
- derive package sets from profile, hardware, desktop, encryption, and snapshots
- manage LUKS-specific hook and mapper logic
- manage snapshot provider package and post-install setup snippets
- expose reusable functions without owning user interface rendering

### Execution Layer

- `installer/executor.sh`

Responsibilities:

- partitioning and formatting
- mount lifecycle
- pacstrap execution
- chroot provisioning
- bootloader install
- fail-fast validation and cleanup

The execution layer consumes state and logic-layer functions. It must not own dialog UI.

## Shared Config Object

Phase 3 introduces:

- `/tmp/install_config.json`

This file is synchronized from installer state and contains:

- disk device and layout choices
- filesystem and boot mode
- encryption settings
- desktop and profile choices
- runtime hardware detection
- optional feature toggles such as zram and snapshots

The JSON file is meant to be the stable handoff format for future plugins, tests, and external automation.

## Module Registry

Phase 3 introduces:

- `installer/core/module-registry.sh`

Modules register themselves through a simple contract:

- `register_*_module`
- optional runner function

Current built-in module families:

- config
- packages
- hardware
- luks
- snapshots

This provides a path toward richer `register()` and `run()` semantics without requiring a rewrite of existing modules.

## Disk Manager Direction

The disk manager remains UI-driven in Phase 3, but its semantics now align with a modular architecture:

- disk discovery uses model-aware metadata
- strategy selection distinguishes automatic and manual flows
- filesystem selection remains a separate persisted configuration step

Future expansion should move partition plans into an explicit disk-plan object that the executor can consume directly.

## Encryption Model

Phase 3 adds optional LUKS2 support for root installs:

- format root partition as LUKS2 when enabled
- open a stable mapper name (`cryptroot` by default)
- format and mount the filesystem inside the mapper
- update mkinitcpio hooks for encrypted boot
- inject encrypted-root kernel parameters

## Snapshot Model

Phase 3 adds snapshot provider selection:

- `none`
- `snapper`
- `timeshift`

For Btrfs installs, `snapper` is the default production-oriented path. The module owns package selection and post-install setup snippets.

## Package Strategy Engine

Package resolution now has a dedicated entry point:

- `resolve_package_strategy()`

Inputs:

- base profile
- editor and tool choices
- desktop profile and display manager
- hardware/runtime detection
- secure boot mode
- snapshot provider
- LUKS enablement

Outputs:

- de-duplicated pacstrap package list

## Hardware Detection V2

Hardware detection now exposes structured data:

- CPU vendor
- GPU vendor
- environment type
- JSON summary persisted in state

This is the basis for future driver policy, VM tuning, and desktop defaults.