# Install

## Live ISO Preparation

Run the installer from the Arch Linux live ISO as root.

Recommended bootstrap:

```bash
loadkeys us
setfont ter-v16n
pacman-key --init
pacman-key --populate archlinux
pacman -Sy archlinux-keyring --noconfirm
pacman -S --needed --noconfirm git dialog reflector
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
git clone https://github.com/emrecanymz9/archinstall-framework.git
cd archinstall-framework
bash installer/install.sh
```

## Safety Model

The installer defaults to `INSTALL_SAFE_MODE=true`.

Safety protections include:

- live disk analysis before strategy selection
- explicit disk previews with exact operations
- typed `YES` for destructive disk actions
- typed `YES` before the full install starts
- rejection of missing disk selections before install
- non-fatal fallback for optional modules and Secure Boot tooling

## Disk Setup

The disk menu supports:

- full wipe
- initialize disk with GPT
- free-space install
- dual-boot install
- manual partition selection

New or empty disks are valid install targets.
If no partition table is present, the UI shows:

- `No partition table detected (new disk)`

If a disk looks damaged, the installer offers initialization instead of failing immediately.

## Install Configuration

The install profile flow captures:

- hostname
- timezone
- locale
- keyboard layout
- username
- user password
- root password
- filesystem
- zram preference
- Secure Boot mode
- install profile
- desktop profile
- display mode
- greeter frontend

Package selection is driven from [config/system.conf](../config/system.conf).
Only visible user packages appear in the custom package flow.

## Supported Environments

The framework is designed to run in:

- VMware
- VirtualBox
- QEMU/KVM
- real hardware

Virtualized environments still install normally, but Secure Boot enrollment is intentionally conservative.

## After Installation

The installer shows a completion dialog and keeps the install log at:

- `/tmp/archinstall_install.log`

For more detail on the internal phases, see [docs/INSTALL_FLOW.md](INSTALL_FLOW.md).