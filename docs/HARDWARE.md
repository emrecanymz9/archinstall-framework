# Hardware Abstraction

## Virtualization Detection

The installer detects common virtualized environments through `systemd-detect-virt` and DMI data.

Supported mappings:

- VMware -> `open-vm-tools`
- VirtualBox -> `virtualbox-guest-utils`
- QEMU/KVM -> `spice-vdagent`, `qemu-guest-agent`

The generated chroot configuration enables guest services only when the related unit files exist.

## GPU Detection

GPU vendor detection uses `lspci`.

Current driver policy:

- Intel -> `mesa`
- AMD -> `mesa`
- NVIDIA -> `nvidia`, `nvidia-utils`
- unknown GUI hardware -> `mesa`

The installer only adds GPU packages automatically for graphical desktop installs.

## Desktop Service Defaults

For KDE installs the target system enables:

- Bluetooth when the service is present
- PipeWire and WirePlumber user services through default user target symlinks

This keeps desktop audio and Bluetooth behavior consistent across bare metal and supported virtual machines.

## Conflict Avoidance

The hardware layer is intentionally conservative:

- it does not install all GPU stacks at once
- it only enables virtualization services that match the detected platform
- it keeps headless installs free of unnecessary desktop GPU packages