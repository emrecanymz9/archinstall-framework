# Secure Boot

## Detection

The installer detects:

- boot mode: BIOS or UEFI
- Secure Boot state through EFI variables when available
- firmware setup mode through EFI variables when available

Boot mode always falls back to `bios` when EFI is not present.

Detected values are shown in the UI headers and summaries.

## Modes

### Disabled

Default behavior.

- no Secure Boot packages are added
- no Secure Boot configuration is attempted
- the normal initramfs and standard systemd-boot entry remain in place

### Assisted

Recommended safe-preparation mode.

- adds `sbctl` and `systemd-ukify` to the target package set on UEFI systems
- records Secure Boot follow-up guidance in `/root/ARCHINSTALL_SECURE_BOOT.txt`
- creates `sbctl` keys in the target system if they do not already exist
- writes `/etc/kernel/cmdline`
- prepares mkinitcpio UKI presets under `/etc/mkinitcpio.d/linux.preset`
- builds UKIs through `mkinitcpio` and `ukify`
- signs generated EFI binaries with `sbctl` when possible
- attempts `sbctl enroll-keys -m` only when firmware reports setup mode and the environment is not virtualized
- never fails the install if the Secure Boot steps are not available

### Advanced

Tooling-only mode.

- adds `sbctl` and `systemd-ukify`
- records the follow-up note
- builds the UKI path like assisted mode
- leaves automatic key enrollment to manual operator control

## Current Safety Model

The installer treats Secure Boot as a best-effort boot-chain preparation step, not as a hard install prerequisite.

That means:

- BIOS installs ignore Secure Boot entirely
- UEFI installs continue even if Secure Boot is enabled in firmware
- the installer does not brick the target by failing hard on missing key-enrollment conditions
- if `sbctl` or `ukify` is unavailable, the installer falls back to a standard initramfs rebuild

## UKI Pipeline

When Secure Boot mode is enabled on UEFI installs, the target configuration performs:

- mkinitcpio configuration
- `/etc/kernel/cmdline` generation
- UKI output under `/boot/EFI/Linux/`
- signing via `sbctl sign -s`

For systemd-boot, the legacy `arch.conf` entry is removed and sd-boot discovers the UKI automatically.

## Edge Cases

### Virtual Machines

- Secure Boot state is still detected
- automatic enrollment is skipped in virtualized environments
- the install continues even if the VM firmware does not support the expected enrollment flow

### Missing Tooling

- if `sbctl` is missing, the installer rebuilds the normal initramfs and continues
- if `ukify` is missing, the installer rebuilds the normal initramfs and continues
- these cases are warnings, not fatal errors

### NVIDIA

- `MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)` is written into `mkinitcpio.conf`
- `nvidia_drm.modeset=1` is appended to the kernel command line used for the UKI

## Operator Guidance

The target system receives `/root/ARCHINSTALL_SECURE_BOOT.txt` with the detected firmware state and recommended commands:

- `sbctl status`
- `sbctl create-keys`
- `sbctl enroll-keys -m`
- `sbctl verify`

This keeps the workflow explicit and reversible on systems where firmware key enrollment requires careful operator control.

## Scope

The pipeline is automated where it is safe to do so, but still degrades to warnings when firmware ownership, signing, or VM behavior prevents a clean Secure Boot handoff.