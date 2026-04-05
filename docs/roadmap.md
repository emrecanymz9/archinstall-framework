# Roadmap

## Current Phase

Phase 4: installer hardening and workflow cleanup.

The project already has the core pipeline, disk manager, bootloader backends, and post-install framework. The current focus is making the installer deterministic, easier to use, and safer to maintain.

## Audit Summary

Completed in this pass:

- split pacstrap into mandatory core packages and validated optional packages
- removed runtime `unknown` disk output in favor of `hdd|ssd|nvme|vm`
- separated disk target selection from partition strategy selection
- replaced the old `disk/config/install/state` menu with a staged installer flow
- removed the ambiguous `modules/` directory in favor of `core`, `ui`, `validation`, `boot`, and `postinstall`
- corrected target log export to `/var/log/archinstall.log` and `/home/$USER/install.log`
- hardened password application, shadow handling, and chroot environment injection
- added greetd session wrapper, validation, and failure logging
- refreshed the architecture, features, state, and chroot docs

## Near-Term Roadmap

1. Validate the full installer on a real Arch ISO boot, including KDE login and display-manager startup.
2. Add focused shell validation in CI or a reproducible Linux test environment.
3. Tighten plugin extension points around the new staged flow and directory layout.
4. Expand desktop support only after the current KDE path is stable end to end.

## Remaining Issues

- Full Bash runtime validation was not completed in this workspace because the current host is Windows, not an Arch ISO shell.
- The installer still depends on real hardware or VM testing for disk operations, pacstrap, and chroot behavior.
- Disk shrink and free-space reuse paths still need more runtime validation than syntax checks can provide.
- Limine Secure Boot remains experimental and should be treated as an advanced path.

## Testing Expectations

Minimum validation on an Arch ISO VM:

1. verify the system boots without manual intervention
2. verify LUKS unlock works when enabled
3. verify the graphical login appears when `greetd` or `sddm` is selected
4. verify root and user login work on first boot
5. verify `/var/log/greetd-boot.log` is created when greetd fails

## Exit Criteria For This Phase

This phase is complete when all of the following are true:

- core pacstrap packages are never skipped
- staged UI flow is stable in dialog and TTY modes
- KDE installs boot into the selected display manager reliably
- documentation matches the shipped behavior
- shell syntax and smoke validation run automatically in a Linux environment
