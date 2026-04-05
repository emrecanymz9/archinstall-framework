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

## Storage And Recovery

- full-disk wipe
- disk initialization for empty or damaged labels
- free-space install
- dual-boot preparation
- manual partition reuse
- ext4 and btrfs
- optional LUKS2 root encryption
- snapper on btrfs installs
- 1 GiB EFI sizing on guided installs

## Desktop And Display

- KDE desktop profile
- display session selection: `wayland|x11`
- display manager selection: `sddm|greetd|none`
- greetd greeter selection: `tuigreet|qtgreet|none`
- explicit display state with no fallback auto-selection during apply

## Boot

- `systemd-boot`
- `grub`
- `limine`
- Secure Boot foundation mode

## Package System

- mandatory core pacstrap packages that are never validated away
- optional package validation only for non-core layers
- deterministic base, required, profile, hardware, desktop, and feature layers
- optional checklist packages: `firefox`, `keepassxc`, `vscode`, `fastfetch`
- GPU-aware package mapping
- Steam-aware 32-bit graphics userspace additions

## Postinstall

- service enablement in one place
- graphical target enforcement
- log export to `/var/log/archinstall.log` and `/home/$USER/install.log`
