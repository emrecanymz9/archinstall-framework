# ArchInstall Framework

A deterministic, modular, Bash-based Arch Linux installer for advanced users who want a clean, reproducible setup — without having to remember every command.

---

## What it is

ArchInstall Framework is a **dialog-based terminal installer** that guides you through a full Arch Linux installation with KDE Plasma 6, covering:

- Disk partitioning (three modes)
- Optional LUKS2 full-disk encryption
- btrfs (with snapshots + compression) or ext4
- Limine or systemd-boot + UKI bootloader
- Full KDE Plasma 6 + Wayland stack
- Gaming tools (Steam, MangoHud, GameMode, Lutris)
- Dev / cybersecurity tools
- Secure Boot via sbctl
- ZRAM (always enabled, no swapfile)

The installer runs in **two phases**:

| Phase | Name | Runs in | What it does |
|-------|------|---------|-------------|
| Phase 1 | **Installer** | Arch ISO (live) | Disk, encrypt, filesystem, base system, bootloader, user accounts |
| Phase 2 | **Post Install** | Installed system (first boot) | KDE, GPU drivers, audio, gaming, dev tools, Secure Boot |

---

## Goals

- **Simple UX, safe defaults** — dialog-based menus, never silently wipes
- **Deterministic** — fixed package sets, clear phase separation
- **Modular** — each concern lives in its own script
- **Strict Bash** — `set -Eeuo pipefail` everywhere
- **Resumable** — state tracked in `config/state.json` via `jq`

---

## How to run (from Arch ISO)

```bash
# 1. Boot the Arch Linux ISO and get a terminal
# 2. Install dependencies
pacman -Sy --needed dialog jq git parted cryptsetup dosfstools btrfs-progs \
    e2fsprogs efibootmgr arch-install-scripts

# 3. Clone this repository
git clone https://github.com/emrecanymz9/archinstall-framework.git
cd archinstall-framework

# 4. Run Phase 1 (Installer)
./installer/install.sh
```

Post Install (Phase 2) runs automatically on first boot. You can also run it manually:

```bash
sudo /opt/archinstall/postinstall/install.sh
```

---

## Supported install modes

### 1. Full disk wipe
Erases the entire selected disk and creates a fresh partition table.

- UEFI → GPT with 512 MiB ESP + root
- BIOS → MBR with one root partition

**Use when:** Installing Arch as the only OS on a disk.

### 2. Free-space install (dual-boot safe)
Uses only **unallocated (free) space** on the disk. Existing partitions (Windows, data, etc.) are **never touched**.

- The installer detects all free segments and shows their sizes
- Warns if available space is below the recommended 80 GiB
- If no free space exists: clear instructions are shown to shrink Windows using Disk Management

> **The installer will never shrink NTFS partitions automatically.**

**Use when:** Dual-booting alongside Windows (or another OS).

### 3. Reinstall on existing Linux partition (wipe Linux only)
Lets you select an existing Linux partition (ext4, btrfs, xfs, crypto_LUKS, etc.) and reinstall on it. Non-Linux partitions (NTFS, Windows Recovery, FAT/Windows) cannot be selected.

**Use when:** You had a previous Linux install and want a clean reinstall.

---

## Safety model

- Disk model, size, and serial number are shown before any destructive action
- Free-space segments are listed with sizes before partitioning
- All destructive operations require typing the exact device name to confirm
- Minimum recommended space (80 GiB) is checked and warned about
- NTFS shrinking is never performed

---

## Boot mode

The installer auto-detects your firmware mode and presents a selection:

| Mode | Disk layout | Bootloader options |
|------|------------|-------------------|
| UEFI | GPT + ESP | Limine, systemd-boot + UKI |
| BIOS | MBR | Limine only |

Firmware instructions are shown for each mode. You can exit to adjust firmware settings and re-run.

---

## Encryption and filesystem matrix

| Encryption | Filesystem | Notes |
|-----------|-----------|-------|
| LUKS2     | btrfs     | Recommended – snapshots + compression + encryption |
| LUKS2     | ext4      | Simple encrypted setup |
| None      | btrfs     | Snapshots without encryption |
| None      | ext4      | Classic, simple |

btrfs uses:
- Compression: `zstd:5`
- Subvolumes: `@` (root), `@home`, `@snapshots`
- Mount options: `noatime,compress=zstd:5,space_cache=v2`

---

## ZRAM and swap policy

- **ZRAM is always enabled** — configured via `zram-generator` (compressed RAM-based swap)
- **Swapfile: not supported** in this framework (btrfs swapfile requires extra configuration)
- **Swap partition: not created** — ZRAM provides enough for most desktop workloads

ZRAM settings:
```ini
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
```

Kernel swappiness is tuned for ZRAM (`vm.swappiness=180`).

---

## Identity: hostname vs. username

When asked during Phase 1:

| Field | What it is | Example |
|-------|-----------|---------|
| **Hostname** (computer name) | Visible on network; appears in terminal prompt after `@` | `my-arch-pc` |
| **Username** | Your Linux login name; appears before `@` in prompt | `john` |

Your terminal prompt will look like: `john@my-arch-pc:~$`

Rules:
- Hostname: lowercase, letters/digits/hyphens, 1–63 chars
- Username: lowercase, letters/digits/underscores/hyphens, 1–32 chars

---

## Bootloader options

### Limine (default)
- Fast, minimal, supports UEFI and BIOS
- Config: `/boot/limine/limine.conf`
- UEFI: EFI binary registered with `efibootmgr`
- BIOS: installed to disk MBR

### systemd-boot + UKI (UEFI only)
- Generates a Unified Kernel Image (kernel + initrd + cmdline in one EFI binary)
- Simplifies Secure Boot signing (sign one file instead of many)
- Config via `/etc/kernel/cmdline` and `/etc/mkinitcpio.d/linux-zen.preset`
- Boot entries auto-discovered from `/boot/EFI/Linux/*.efi`

---

## Phase 2 modules

| Module | File | What it installs |
|--------|------|-----------------|
| GPU drivers | `modules/gpu.sh` | NVIDIA/AMD/Intel drivers, Vulkan |
| Audio | `modules/audio.sh` | PipeWire, WirePlumber, pavucontrol |
| Network | `modules/network.sh` | NetworkManager tools, nss-mdns |
| Bluetooth | `modules/bluetooth.sh` | bluez, auto-enable |
| Gaming | `modules/gaming.sh` | Steam, GameMode, MangoHud, Lutris, Wine |
| Secure Boot | `modules/secureboot.sh` | sbctl key enrollment and signing |
| Backup | `modules/backup.sh` | snapper (btrfs) or Timeshift (ext4) |
| Dev tools | `modules/devtools.sh` | neovim, git, docker, rust, nmap, etc. |
| ZRAM | `modules/zram.sh` | zram-generator config + sysctl tuning |

---

## Secure Boot

Secure Boot setup runs in Phase 2 (after the system is installed and booted). This avoids conflicts with the ISO boot process.

The `modules/secureboot.sh` module:
1. Checks if the system is in Setup Mode (required for key enrollment)
2. Creates custom Secure Boot keys with `sbctl`
3. Enrolls keys (including Microsoft CA for hardware compatibility)
4. Signs all EFI binaries

To enable Secure Boot after Phase 2:
1. Enter firmware (UEFI) settings
2. Clear factory Secure Boot keys → enable **Setup Mode**
3. Reboot into Arch
4. Run: `sudo /opt/archinstall/modules/secureboot.sh`
5. Reboot → firmware → enable **Secure Boot**

---

## Logging and troubleshooting

| Phase | Log location |
|-------|-------------|
| Phase 1 | `/tmp/archinstall.log` |
| Phase 2 | `/var/log/archinstall-phase2.log` |

```bash
# View Phase 1 log
cat /tmp/archinstall.log

# View Phase 2 log
journalctl -u archinstall-phase2.service
cat /var/log/archinstall-phase2.log

# Check Phase 2 service status
systemctl status archinstall-phase2.service

# Re-run Post Install manually
rm /var/lib/archinstall/phase2-done
sudo /opt/archinstall/postinstall/install.sh
```

---

## Dialog TUI – readable text guaranteed

The installer automatically ensures the dialog TUI is always readable:

- **`TERM` is set automatically** — If `TERM` is unset or set to `dumb` (common on early boot or plain SSH sessions), the installer sets it to `linux` (on a TTY) or `xterm-256color` (otherwise) before any dialog call.  You do not need to export `TERM` manually.
- **`NO_COLOR=1` is exported** — This signals all subprocesses (pacman, lsblk, etc.) to suppress ANSI color output, so no raw escape sequences can leak into dialog text.
- **Text is sanitised** — All strings passed to dialog are filtered to strip any remaining real (`ESC[`) and literal (`\e[`, `\033[`, `\x1b[`) escape sequences.

### What used to go wrong

Without these safeguards, dialog windows could display garbled text like `\[0;10m` or `\033[1;32m` instead of readable content.  This happened when `TERM` was unset (dialog fell back to raw escape codes) or when a tool wrote ANSI codes that ended up inside a message box.

### Override

If you need colour output from other scripts running alongside the installer, unset `NO_COLOR` after sourcing `ui.sh`:

```bash
unset NO_COLOR
```

If you need a specific terminal type, export it **before** sourcing `ui.sh`:

```bash
export TERM=xterm-256color
source /path/to/installer/ui.sh
```

---

## Directory structure

```
archinstall-framework/
├── installer/
│   ├── install.sh      # Phase 1 orchestrator (Installer)
│   ├── bootmode.sh     # UEFI/BIOS detection and selection
│   ├── disk.sh         # Disk selection, install modes, partitioning
│   ├── filesystem.sh   # btrfs/ext4 formatting and mounting
│   ├── luks.sh         # LUKS2 encryption setup
│   ├── limine.sh       # Limine + systemd-boot/UKI bootloader
│   ├── microcode.sh    # CPU microcode detection
│   ├── executor.sh     # Logging, run_cmd, chroot_run
│   ├── state.sh        # State management (config/state.json)
│   └── ui.sh           # dialog wrappers with adaptive sizing
├── postinstall/
│   ├── install.sh      # Phase 2 orchestrator (Post Install)
│   └── desktops/
│       └── kde.sh      # KDE Plasma 6 desktop install flow
├── modules/
│   ├── gpu.sh          # GPU driver detection/install
│   ├── audio.sh        # PipeWire stack
│   ├── network.sh      # Network tools
│   ├── bluetooth.sh    # Bluetooth
│   ├── gaming.sh       # Steam, MangoHud, GameMode, Lutris
│   ├── secureboot.sh   # Secure Boot via sbctl
│   ├── backup.sh       # snapper / Timeshift
│   ├── devtools.sh     # Dev + cybersec tools
│   └── zram.sh         # ZRAM configuration
├── config/
│   └── state.json      # Installation state (tracked by jq)
└── README.md
```
