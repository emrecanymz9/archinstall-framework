# Features

## Runtime Detection

- boot mode
- Secure Boot state and setup mode
- environment vendor and virtualization type
- CPU vendor
- GPU vendor
- disk model, transport, and disk type

Disk types are normalized to:

- `NVMe SSD`
- `SATA SSD`
- `HDD`
- `VM Disk`

## Install Profiles

- `daily`
- `dev`
- `custom`

## UI And Workflow

- staged installer flow: `Disk -> Partition -> Desktop -> Display manager -> Packages -> Summary -> Install`
- short on-screen tips for destructive or confusing steps
- dialog-first UI with TTY fallback
- inline validation for usernames, passwords, and package input
- checklist dialogs default to the confirmation button to reduce navigation friction
- invalid input reopens the same dialog instead of dropping to an empty screen

## Storage And Recovery

- full-disk wipe
- disk initialization for empty or damaged labels
- free-space install
- dual-boot preparation
- manual partition reuse
- ext4 and btrfs
- optional LUKS2 root encryption
- bootloader-aware snapshot selection (`snapper` or `timeshift`)
- 1 GiB EFI sizing on guided installs

## Desktop And Display

- KDE desktop profile
- display session selection: `wayland|x11`
- display manager selection: `sddm|greetd|none`
- greetd greeter selection: `tuigreet|qtgreet|none`
- explicit display state with no fallback auto-selection during apply

## Boot

- capability-based selection for `systemd-boot`, `grub`, and `limine`
- recommendation tags in the UI (`recommended`, `advanced`, `experimental`)
- Secure Boot foundation mode with a UKI-oriented path for `systemd-boot`
- explicit advanced-path behavior for GRUB and Limine when Secure Boot is involved

## Package System

- mandatory core pacstrap packages that are never validated away
- optional package validation only for non-core layers
- deterministic base, required, profile, hardware, desktop, and feature layers
- optional checklist packages: `firefox`, `keepassxc`, `vscode`, `fastfetch`
- GPU-aware package mapping
- Steam-aware 32-bit graphics userspace additions

## Postinstall

- service enablement in one place
- display-manager configuration inside chroot
- graphical target enforcement
- greetd validation before service enablement
- greetd failure logging to `/var/log/greetd-boot.log`
- log export to `/var/log/archinstall.log` and `/home/$USER/install.log`

## Password Handling

- user creation before password application
- root and user passwords applied non-interactively with `chpasswd`
- empty passwords handled through `passwd -d`
- `/etc/shadow` ownership and mode normalized before password writes
- password failures abort the install instead of degrading silently
