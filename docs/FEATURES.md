# Features

## Runtime Detection

- Boot mode detection for BIOS and UEFI
- Secure Boot firmware state and setup-mode detection
- Virtualization vendor detection for VMware, VirtualBox, QEMU/KVM, and Hyper-V
- CPU and GPU vendor detection used by package strategy
- Disk model, transport bus, and coarse disk-type reporting in the UI and manifest

## Install Profiles

- `daily`: KDE-first workstation flow with reduced prompts
- `dev`: developer-focused profile with editor and VS Code choices
- `custom`: explicit package, desktop, and optional-feature selection

## Desktop And Login

- KDE Plasma desktop profile
- Deterministic display session selection: `wayland` or `x11`
- Deterministic display manager selection: `sddm`, `greetd`, or `none`
- greetd frontend selection: `tuigreet`, `qtgreet`, or `none`
- Strict enable/disable behavior so only the chosen display manager is active in the target system

## Storage

- Full-disk wipe installs
- GPT initialization for blank or unreadable disks
- Free-space installs
- Windows-aware dual-boot preparation
- Manual partition reuse with EFI validation
- Btrfs subvolume layout: `@`, `@home`, `@var`, `@snapshots`
- Disk-space validation before pacstrap

## Security And Recovery

- Optional LUKS2 root encryption
- Secure Boot foundation mode with `sbctl` and UKI preparation
- Non-fatal Secure Boot workflow for imperfect firmware or VM environments
- Snapper integration for btrfs installs with timeline and cleanup timers
- BIOS plus GPT safety checks before GRUB install

## Package Strategy

- Config-driven base and required package sets from `config/packages.conf`
- GPU-aware driver selection for Intel, AMD, NVIDIA, and virtualized systems
- CPU microcode package selection
- Guest tools for supported hypervisors
- Optional Steam support with multilib enablement and 32-bit graphics userspace
- Optional zram and VS Code support
- Plugin-contributed packages merged into the final pacstrap set

## UX And Operations

- Dialog-first UI with TTY fallback
- Live progress output with recent log lines
- Saved installer state summaries
- Install manifest and copied install log in the target user home directory
