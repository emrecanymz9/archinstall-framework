# Secure Boot

## Detection

The installer detects:

- boot mode: BIOS or UEFI
- Secure Boot state through EFI variables when available
- firmware setup mode through EFI variables when available

Detected values are shown in the UI headers and summaries.

## Modes

### Disabled

Default behavior.

- no Secure Boot packages are added
- no Secure Boot configuration is attempted

### Assisted

Recommended safe-preparation mode.

- adds `sbctl` to the target package set on UEFI systems
- records Secure Boot follow-up guidance in `/root/ARCHINSTALL_SECURE_BOOT.txt`
- creates `sbctl` keys in the target system if they do not already exist
- attempts `sbctl enroll-keys -m` only when firmware reports setup mode
- never fails the install if the Secure Boot steps are not available

### Advanced

Tooling-only mode.

- adds `sbctl`
- records the follow-up note
- does not attempt automatic key enrollment unless explicitly handled later by the operator

## Current Safety Model

The installer treats Secure Boot as a best-effort boot-chain preparation step, not as a hard install prerequisite.

That means:

- BIOS installs ignore Secure Boot entirely
- UEFI installs continue even if Secure Boot is enabled in firmware
- the installer does not brick the target by failing hard on missing key-enrollment conditions

## Operator Guidance

The target system receives `/root/ARCHINSTALL_SECURE_BOOT.txt` with the detected firmware state and recommended commands:

- `sbctl status`
- `sbctl create-keys`
- `sbctl enroll-keys -m`
- `sbctl verify`

This keeps the workflow explicit and reversible on systems where firmware key enrollment requires careful operator control.

## Scope

The current implementation prepares the system and the tooling safely.
It does not force a fully automated UKI pipeline, because firmware ownership and signing policy vary too much to automate blindly in a generic Arch ISO installer.