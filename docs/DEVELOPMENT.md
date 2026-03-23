# Development

## Repository Structure

Core runtime paths:

- [installer/install.sh](../installer/install.sh): UI and orchestration
- [installer/executor.sh](../installer/executor.sh): install execution and chroot configuration
- [installer/disk.sh](../installer/disk.sh): disk selection flow
- [installer/core/hooks.sh](../installer/core/hooks.sh): plugin hooks and menu registry
- [installer/modules](../installer/modules): optional feature modules

## Development Commands

Useful Make targets from the repository root:

- `make deps`
- `make mirror`
- `make run`
- `make full-deps`

`make full-deps` is intended for development machines, not the live ISO.

## Design Rules

The framework follows these rules:

- all optional modules must degrade safely
- plugin failures must not stop the installer
- destructive disk actions must be previewed and confirmed
- runtime detection must avoid blocking the UI
- package selection must come from [config/system.conf](../config/system.conf)

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