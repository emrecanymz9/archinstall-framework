# Development

## Repository Structure

Core runtime paths:

- [installer/install.sh](../installer/install.sh): UI and orchestration
- [installer/executor.sh](../installer/executor.sh): install execution and chroot configuration
- [installer/disk.sh](../installer/disk.sh): disk selection flow
- [installer/core/state.sh](../installer/core/state.sh): shared state primitives
- [installer/core/hooks.sh](../installer/core/hooks.sh): plugin hooks and menu registry
- [installer/modules/detect.sh](../installer/modules/detect.sh): shared runtime and hardware detection
- [installer/modules](../installer/modules): optional feature modules

## Development Commands

Useful Make targets from the repository root:

- `make deps`
- `make install`
- `make clone`
- `make mirror`
- `make run`
- `make full-deps`
- `make clean`

`make full-deps` is intended for development machines, not the live ISO.

## Design Rules

The framework follows these rules:

- all optional modules must degrade safely
- plugin failures must not stop the installer
- destructive disk actions must be previewed and confirmed
- runtime detection must avoid blocking the UI
- package selection must come from [config/packages.conf](../config/packages.conf)

`config/system.conf` is retained only as a compatibility wrapper.

## Cleanup Strategy

The repository cleanup target is intentionally conservative.

Safe cleanup paths:

- `/tmp/archinstall_state`
- `/tmp/archinstall_debug.log`
- `/tmp/archinstall_install.log`
- `/tmp/archinstall_progress.log`
- editor swap and patch leftovers: `*.swp`, `*.tmp`, `*.bak`, `*.orig`, `*.rej`
- transient cache directories such as `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`

Use `bash scripts/cleanup.sh` or `make clean` from the repository root.

## Notes Carried Forward

The original project notes emphasized these development priorities:

- keep detection reliable for VMs and real hardware
- list disks with clear model information when firmware reports it
- keep package relationships explicit instead of relying on hidden assumptions
- document strategy decisions and recovery paths

## Recommended Test Matrix

Before shipping changes, test at least:

- empty disk in VMware
- empty disk in VirtualBox
- existing partition table on bare metal or a realistic VM image
- UEFI install with Secure Boot disabled
- UEFI install with Secure Boot enabled and tooling present
- NVIDIA path with Secure Boot enabled
- custom profile with user-visible package selection only