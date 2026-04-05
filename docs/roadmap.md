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
- removed dead system wrapper modules that were no longer part of the active architecture
- corrected target log export to `/var/log/archinstall.log` and `/home/$USER/install.log`
- refreshed the architecture, features, and state docs

## Near-Term Roadmap

1. Validate the full installer on a real Arch ISO boot, including KDE login and display-manager startup.
2. Add focused shell validation in CI or a reproducible Linux test environment.
3. Continue pruning unused modules and tighten plugin extension points around the new staged flow.
4. Expand desktop support only after the current KDE path is stable end to end.

## Remaining Issues

- Full Bash runtime validation was not completed in this workspace because the current host is Windows, not an Arch ISO shell.
- The installer still depends on real hardware or VM testing for disk operations, pacstrap, and chroot behavior.
- Bootloader selection remains deterministic by boot mode; there is not yet a dedicated bootloader screen in the staged UI.

## Exit Criteria For This Phase

This phase is complete when all of the following are true:

- core pacstrap packages are never skipped
- staged UI flow is stable in dialog and TTY modes
- KDE installs boot into the selected display manager reliably
- documentation matches the shipped behavior
- shell syntax and smoke validation run automatically in a Linux environment
