# ArchInstall Framework

A modular, Bash-based Arch Linux installer designed as a **daily OS** — custom, modern, and inspired by CachyOS but built from scratch for any hardware. Run it on a PC, laptop, server, or a VM (for testing). It works anywhere you have a Linux TTY/console.

---

## What it is

ArchInstall Framework is a **step-by-step TUI installer** that guides you through a full Arch Linux installation with KDE Plasma 6, covering:

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

> **VM usage:** A VM (VMware, VirtualBox, QEMU, etc.) is a fully supported platform — great for testing before deploying to real hardware, but also valid as a permanent install target.

---

## Goals

- **Universal platform** — PC, laptop, desktop, console, or VM; any environment with a Linux TTY
- **Full TUI dialog installer** — all steps driven by dialog menus (like CachyOS), custom and modular
- **Bash fallback for debugging** — when `dialog` is not installed, every prompt automatically falls back to plain bash (`select`, `read`, yes/no via Enter) so you can test on a minimal system
- **Simple UX, safe defaults** — dialog menus, never silently wipes
- **Deterministic** — fixed package sets, clear phase separation
- **Modular** — each concern lives in its own script
- **Strict Bash** — `set -Eeuo pipefail` everywhere
- **Resumable** — state tracked in `config/state.json` via `jq`

---

## UI modes: dialog TUI vs. bash fallback

The installer supports two UI modes that are selected automatically:

| Mode | When | How it looks |
|------|------|-------------|
| `dialog` | `dialog` package is installed (default on Arch ISO) | Full TUI with bordered windows, arrow-key navigation |
| `bash` | `dialog` not installed, or `UI_MODE=bash` is set | Plain terminal prompts: numbered menus, `[y/n]`, Enter to confirm |

### Forcing bash mode (for debugging / early development)

```bash
# Run in bash fallback mode without dialog
UI_MODE=bash ./installer/install.sh

# Or export for the whole session
export UI_MODE=bash
./installer/install.sh
```

### Forcing dialog mode

```bash
# Install dialog first (standard on Arch ISO)
pacman -Sy --needed dialog
./installer/install.sh
```

When `dialog` is not found and `UI_MODE` is not forced, the installer prints a notice and switches to bash fallback automatically — it never aborts just because `dialog` is missing.

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

> **Minimal / debug run** (no `dialog` needed):
> ```bash
> UI_MODE=bash ./installer/install.sh
> ```

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

## Troubleshooting: dialog shows escape sequences / unreadable text

> **Quickest fix: switch to bash fallback mode**
> ```bash
> UI_MODE=bash ./installer/install.sh
> ```
> This skips `dialog` entirely and uses plain bash prompts — useful when testing
> or when the environment doesn't cooperate with ncurses.

If `dialog` boxes display raw escape sequences such as `\E[0m`, `\033[32m`, or
`^[[1m` instead of readable text, the cause is almost always one of these:

### 1. `TERM` is unset or set to an unknown value

`dialog` needs a valid terminal type to render its UI. The installer sets
`TERM=linux` automatically when the variable is unset, but if you export an
unknown value beforehand the fix is:

```bash
export TERM=linux          # safe for any Linux TTY / VM console
# or, for a full-colour terminal emulator:
export TERM=xterm-256color
```

### 2. Running inside a terminal multiplexer with a mismatched `TERM`

If you launch the installer from inside `tmux` or `screen` but `TERM` is not
set to match (e.g. `TERM=tmux-256color` when dialog was built without that
terminfo entry), set:

```bash
export TERM=xterm-256color
./installer/install.sh
```

### 3. VMware / VirtualBox console

On a raw VM console (not an SSH session), use:

```bash
export TERM=linux
./installer/install.sh
```

**Dialog does not appear after "Step 1" — must press Enter**

This is a known issue on VM/TTY consoles (VMware Workstation, VirtualBox) where
the Linux line-discipline is in a non-standard state after text is printed to the
terminal.  The installer now calls `stty sane` before every `dialog` invocation
and runs `clear` before the first dialog window, so this should no longer occur.
If you still experience it, run:

```bash
stty sane
./installer/install.sh
```

**Disk not detected ("No installable disks detected")**

In VMware, disks often have empty `MODEL` and `SERIAL` fields.  Earlier versions
of the installer used `lsblk` column-counting that misidentified the `TYPE` field
when `MODEL`/`SERIAL` were blank, causing all disks to be silently skipped.  The
fix uses `lsblk --pairs` (`-P`) output which encodes every field as `KEY="value"`,
so empty fields are parsed correctly.

If you still see "No installable disks detected", verify the disk is visible:

```bash
# Should list your disk (e.g. sda, sdb, nvme0n1)
lsblk -d -o NAME,SIZE,MODEL,TYPE

# Direct kernel view — always lists all block devices
ls /sys/block/

# Detailed pairs output (what the installer uses)
lsblk -d -P -o NAME,SIZE,MODEL,SERIAL,TYPE --bytes
```

In VMware: go to **VM → Settings → Hardware → Add → Hard Disk** and make sure
the disk is connected (not just added to configuration).  The disk does not need
to be formatted or partitioned — the installer handles that.

**Garbled / unreadable text inside dialog windows**

Characters like `?7l`, `?1000h`, or `^[` appearing in dialog text are DEC private
VT sequences that some `dialog`/ncurses versions write to stderr alongside the
selected value.  The installer now strips these from every `dialog` return value
using an extended `strip_ansi()` pattern that covers `\033[?…`, `\033[>…`, and
`\033[!…` sequences in addition to standard CSI sequences.

### What the installer does to prevent this

* `installer/ui.sh` sets `TERM` automatically — `linux` on a physical/virtual
  console (TTY), `xterm-256color` on non-TTY sessions (SSH, pipes, etc.).
* `installer/ui.sh` exports `NO_COLOR=1` so that subprocesses (pacman, lsblk,
  etc.) suppress their own ANSI color output, preventing escape codes from
  leaking into dialog text.
* `require_tools()` smoke-tests `tput` and resets `TERM=linux` if it fails.
* Every string passed to `dialog` is run through `strip_ansi()`, which removes
  both real ESC-byte CSI/OSC sequences (including DEC private sequences such as
  `\033[?7l`, `\033[?1000h`, and mouse-control sequences) and literal
  `\033[…`, `\e[…`, `\x1b[…` patterns, so coloured output from system commands
  is never displayed as raw escape characters inside a dialog box.
* `_dlg()` calls `stty sane` before every `dialog` invocation and sanitizes
  the dialog stderr output (user selections) to strip any stray escape sequences
  written by ncurses/dialog on VM consoles.
* `installer/install.sh` calls `clear` before the first dialog to put the
  terminal in a clean state, preventing the "must press Enter" issue on VMware.
* `list_disks()` uses `lsblk --pairs` (`-P`) output so that disks with empty
  `MODEL`/`SERIAL` (common in VMware) are always detected correctly, with a
  `/sys/block` fallback for environments where `lsblk` is unavailable.

### Quick fixes (if you still see garbage)

```bash
# Disable color output in tools that respect NO_COLOR
NO_COLOR=1 ./installer/install.sh

# Set a well-known TERM value before running the installer
TERM=xterm-256color ./installer/install.sh

# Both together
NO_COLOR=1 TERM=xterm-256color ./installer/install.sh
```

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
│   └── ui.sh           # dialog TUI wrappers + bash fallback (UI_MODE)
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
