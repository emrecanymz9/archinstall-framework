# Known Issues

## Current Limitations

- `qtgreet` is optional and requires a plugin or custom package source to provide the binary.
- Automatic Secure Boot key enrollment is skipped in virtualized environments.
- If `sbctl` or `ukify` is missing, the installer falls back to the normal initramfs path instead of building a UKI.

## Operational Caveats

- The live ISO environment is RAM-backed, so heavy package installs should stay in the target system rather than the ISO session.
- A damaged disk layout can be initialized safely from the disk menu, but this is destructive and still requires confirmation.
- The free-space path expects a readable partition table. New disks should be initialized first or installed through the full-wipe path.

## Areas To Watch During Testing

- firmware that reports incomplete EFI variable state
- vendor disks that do not expose a useful model string
- guest firmware Secure Boot behavior in VMware and VirtualBox
- GPU passthrough or unusual `lspci` output that falls back to `Generic`