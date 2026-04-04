# Features

## Runtime Detection

- boot mode
- Secure Boot state and setup mode
- virtualization vendor
- CPU vendor
- GPU vendor
- disk model, transport, and disk type

## Install Profiles

- `daily`
- `dev`
- `custom`

## Desktop

- KDE desktop profile
- display session selection: `wayland|x11`
- display manager selection: `sddm|greetd|none`
- greetd greeter selection: `tuigreet|qtgreet|none`

## Storage And Recovery

- full-disk wipe
- free-space install
- dual-boot preparation
- manual partition reuse
- ext4 and btrfs
- optional LUKS2 root encryption
- snapper for btrfs installs

## Boot

- `systemd-boot`
- `grub`
- `limine`
- Secure Boot foundation mode

## Package System

- deterministic base and required package layers
- optional checklist packages: `firefox`, `keepassxc`, `vscode`, `fastfetch`
- GPU-aware package mapping
- Steam-aware 32-bit graphics userspace additions

## Postinstall

- service enablement in one place
- graphical target enforcement
- install log export into the target system
