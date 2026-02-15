# 📄 ARCHITECTURE.md

```markdown
# Archinstall Framework – Architecture Specification (2026)

This project is a layered, deterministic Arch Linux installation framework designed for modern 2026 systems.

It is NOT a generic Arch installer.
It is a secure-by-default, recoverable, layered system builder.

---

# Design Philosophy

- Deterministic execution
- Secure by default
- Layered architecture
- No destructive operations before confirmation
- Fully recoverable from TTY
- No optional encryption
- No optional filesystem
- No optional kernel
- Clear separation between configuration and execution

The installer is designed for real-world failure scenarios:
- System updates breaking boot
- Desktop crashes
- Kernel issues
- Secure Boot misconfiguration
- Gaming stack instability

Core system must remain recoverable at all times.

---

# Layered Architecture

The project is divided into independent layers:

Layer 0 – Core Installer  
Layer 1 – Desktop Installer (KDE Wayland)  
Layer 2 – Performance / Gaming  
Layer 3 – Toolsets (Dev / Cybersec / Media)  
Layer 4 – Security & Backup  

Each layer must function independently.
Core layer must never depend on Desktop layer.

---

# Core Installer (Layer 0)

The core installer builds a minimal, encrypted, stable Arch Linux base system.

## Non-Optional Defaults

- LUKS2 encryption
- Btrfs filesystem (compress=zstd:5)
- ZRAM (ram/2, zstd)
- linux-zen kernel
- Limine bootloader
- NetworkManager
- OpenSSH

The following are NOT allowed in core:

- Unencrypted root
- ext4 as default
- GRUB
- systemd-boot
- Desktop environments

---

# Execution Model

The installer must be divided into three phases:

1. Configuration Phase
   - Collect user decisions
   - Detect hardware
   - Build install plan
   - No disk modification

2. Review Phase
   - Display final installation plan
   - Require explicit confirmation

3. Execution Phase
   - Perform disk operations
   - Install packages
   - Configure bootloader
   - No cancellation allowed

No disk operation may occur before Execution Phase.

---

# Disk Strategy

User selects:

- Entire Disk
- Existing Partition

## UEFI Layout

```

/dev/sdX
├── 512M EFI (FAT32)
└── LUKS2 container
└── Btrfs
├── @
├── @home
├── @snapshots

```

ESP mount point:
```

/boot

```

## BIOS Layout

```

/dev/sdX
└── LUKS2 container
└── Btrfs

```

---

# Btrfs Configuration

Subvolumes:

- @
- @home
- @snapshots

Mount options:

```

compress=zstd:5,noatime,ssd,space_cache=v2

```

Snapshots are handled in later layers.

---

# LUKS2 Configuration

- LUKS2 only
- Argon2id
- No keyfile by default
- TPM support may be added later

Encryption is mandatory.

---

# Kernel

The system must use:

- linux-zen
- linux-zen-headers

mkinitcpio hooks must include:

```

base udev autodetect modconf block encrypt filesystems keyboard fsck

```

---

# ZRAM

Swap partition is not used.

ZRAM configuration:

```

zram-size = ram / 2
compression-algorithm = zstd

```

---

# Bootloader

Bootloader is fixed:

- Limine only

No GRUB.
No systemd-boot.

Limine must support:

- BIOS
- UEFI

Root UUID must be dynamically generated in limine.cfg.

---

# Secure Boot

Secure Boot is implemented using:

- sbctl

Secure Boot must:

- Sign linux-zen kernel
- Sign initramfs
- Sign Limine EFI binary

Secure Boot is NOT enabled automatically during core installation.
It is a post-install security step.

---

# Desktop Layer (Layer 1)

Separate installer.

Includes:

- KDE Plasma 6.8
- Wayland + KWin
- greetd + qtgreet
- PipeWire (mandatory)
- Gamescope
- Gamemode
- MangoHud

Audio policy:

- PipeWire is mandatory
- PulseAudio must be removed
- No interactive audio prompts

---

# Performance / Gaming Layer

Includes:

- Gamescope
- Gamemode
- MangoHud

Must not modify core encryption or filesystem logic.

---

# Toolsets Layer

Optional modules:

- Flatpak
- Dev tools
- Cybersec tools
- Media tools
- Terminal customization
- OpenRGB

Must not affect boot integrity.

---

# Backup / Recovery Layer

Includes:

- Snapper / Timeshift
- borgbackup
- restic
- syncthing

Must not be part of core execution path.

---

# Safety Rules

- No module may perform destructive operations outside Execution Phase.
- No global state pollution.
- Every module must be idempotent.
- Installer must be rerunnable.
- Cancel must always be safe before Execution Phase.

---

# Target System Profile (2026)

Final target stack:

KDE Plasma 6.8  
KWin (Wayland)  
greetd + qtgreet  
Limine  
LUKS2  
Btrfs (zstd:-5)  
ZRAM  
PipeWire  
Gamescope  
Gamemode  
MangoHud  
sbctl Secure Boot  
linux-zen  
Flatpak  
Timeshift/Snapper  
OpenRGB  
Dev / Cybersec / Media tools  
borgbackup / restic / syncthing  

This framework is designed to build that system in layered, controlled stages.
```
