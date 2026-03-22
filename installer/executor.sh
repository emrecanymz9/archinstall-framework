#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCHINSTALL_LOG=${ARCHINSTALL_LOG:-/tmp/archinstall_install.log}
ARCHINSTALL_INSTALL_SUCCESS=${ARCHINSTALL_INSTALL_SUCCESS:-false}
ARCHINSTALL_CLEANUP_ACTIVE=${ARCHINSTALL_CLEANUP_ACTIVE:-false}
DEV_MODE=${DEV_MODE:-false}
SKIP_PARTITION=${SKIP_PARTITION:-false}
SKIP_PACSTRAP=${SKIP_PACSTRAP:-false}
SKIP_CHROOT=${SKIP_CHROOT:-false}

# shellcheck source=installer/ui.sh
source "$SCRIPT_DIR/ui.sh"
# shellcheck source=installer/state.sh
source "$SCRIPT_DIR/state.sh"

flag_enabled() {
	case ${1:-false} in
		1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn])
			return 0
			;;
		*)
			return 1
			;;
	esac
}

require_root() {
	if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
		return 0
	fi

	error_box "Root Required" "Run the installer as root from the Arch Linux live environment."
	return 1
}

require_commands() {
	local cmd
	local missing=()

	for cmd in dialog lsblk wipefs parted partprobe mkfs.fat mkfs.ext4 mount umount pacstrap genfstab ping reflector blkid arch-chroot bootctl; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done

	if [[ ${#missing[@]} -eq 0 ]]; then
		return 0
	fi

	error_box "Missing Commands" "Install the required tools before continuing:\n\n${missing[*]}"
	return 1
}

partition_path() {
	local disk=${1:?disk is required}
	local number=${2:?partition number is required}

	case "$disk" in
		*nvme*|*mmcblk*)
			printf '%sp%s\n' "$disk" "$number"
			;;
		*)
			printf '%s%s\n' "$disk" "$number"
			;;
	esac
}

log_line() {
	local message=${1:-}

	printf '[%s] %s\n' "$(date '+%F %T')" "$message" >> "$ARCHINSTALL_LOG"
}

cleanup_mounts() {
	umount -R /mnt >> "$ARCHINSTALL_LOG" 2>&1 || true

	return 0
}

cleanup_install() {
	local reason=${1:-EXIT}

	if [[ ${ARCHINSTALL_CLEANUP_ACTIVE:-false} == true && ${ARCHINSTALL_INSTALL_SUCCESS:-false} != true ]]; then
		log_line "Cleanup triggered by $reason"
		cleanup_mounts || true
		ARCHINSTALL_CLEANUP_ACTIVE=false
	fi

	if [[ $reason == "INT" ]]; then
		exit 130
	fi
}

show_install_error() {
	local step=${1:-"Unknown step"}
	local excerpt

	excerpt="$(tail -n 15 "$ARCHINSTALL_LOG" 2>/dev/null || true)"
	error_box "Installation Failed" "Step failed: $step\n\nRecent log output:\n$excerpt"
}

run_step() {
	local step=${1:?step description is required}

	shift
	progress "Installing" "$step"
	log_line "$step"

	if "$@" >> "$ARCHINSTALL_LOG" 2>&1; then
		return 0
	fi

	show_install_error "$step"
	return 1
}

run_shell_step() {
	local step=${1:?step description is required}
	local command_string=${2:?command string is required}

	progress "Installing" "$step"
	log_line "$step"

	if bash -lc "$command_string" >> "$ARCHINSTALL_LOG" 2>&1; then
		return 0
	fi

	show_install_error "$step"
	return 1
}

run_step_with_retry() {
	local step=${1:?step description is required}
	local max_attempts=${2:?max attempts is required}
	local attempt=1

	shift 2

	while (( attempt <= max_attempts )); do
		progress "Installing" "$step\n\nAttempt $attempt/$max_attempts"
		log_line "$step (attempt $attempt/$max_attempts)"

		if "$@" >> "$ARCHINSTALL_LOG" 2>&1; then
			return 0
		fi

		if (( attempt == max_attempts )); then
			show_install_error "$step"
			return 1
		fi

		attempt=$((attempt + 1))
	done
}

resolve_target_partitions() {
	local disk=${1:?disk is required}
	local efi_partition=""
	local root_partition=""

	efi_partition="$(get_state "EFI_PART" 2>/dev/null || true)"
	root_partition="$(get_state "ROOT_PART" 2>/dev/null || true)"

	[[ -n $efi_partition ]] || efi_partition="$(partition_path "$disk" 1)"
	[[ -n $root_partition ]] || root_partition="$(partition_path "$disk" 2)"

	if [[ ! -b $efi_partition || ! -b $root_partition ]]; then
		error_box "Partition Detection Failed" "Expected partitions were not found:\n\n$efi_partition\n$root_partition"
		return 1
	fi

	printf '%s\n%s\n' "$efi_partition" "$root_partition"
}

run_chroot_configuration() {
	local root_partuuid=${1:?root PARTUUID is required}

	progress "Installing" "Configuring the new system and installing systemd-boot"
	log_line "Configuring the target system inside chroot"

	if arch-chroot /mnt /bin/bash <<EOF >> "$ARCHINSTALL_LOG" 2>&1
set -euo pipefail

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

if ! grep -qx 'en_US.UTF-8 UTF-8' /etc/locale.gen; then
	echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
fi
locale-gen
printf '%s\n' 'LANG=en_US.UTF-8' > /etc/locale.conf

printf '%s\n' 'archlinux' > /etc/hostname
cat > /etc/hosts <<'EOT'
127.0.0.1 localhost
::1       localhost
127.0.1.1 archlinux.localdomain archlinux
EOT

echo 'root:root' | chpasswd
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager

bootctl install
mkdir -p /boot/loader/entries
cat > /boot/loader/loader.conf <<'EOT'
default arch
timeout 3
editor no
EOT

cat > /boot/loader/entries/arch.conf <<EOT
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$root_partuuid rw
EOT
EOF
	then
		return 0
	fi

	show_install_error "Configuring the new system"
	return 1
}

install_base_system() {
	local disk=""
	local efi_partition=""
	local root_partition=""
	local root_partuuid=""
	local confirm_status=0
	local install_status=0
	local dev_notice=""
	local -a resolved_partitions=()

	require_root || return 1
	require_commands || return 1

	disk="$(get_state "DISK" 2>/dev/null || true)"
	if [[ -z $disk ]]; then
		msg "Disk Required" "Select a target disk before starting the installation."
		return 1
	fi

	if [[ ! -b $disk ]]; then
		error_box "Invalid Disk" "The saved disk does not exist anymore:\n\n$disk"
		return 1
	fi

	if flag_enabled "$DEV_MODE"; then
		dev_notice="\n\nDev mode flags:\nSKIP_PARTITION=$SKIP_PARTITION\nSKIP_PACSTRAP=$SKIP_PACSTRAP\nSKIP_CHROOT=$SKIP_CHROOT"
	fi

	confirm "Confirm Installation" "This will prepare a bootable Arch Linux system on:\n\n$disk\n\nDestructive steps may erase existing data.$dev_notice\n\nContinue?" 16 76
	confirm_status=$?
	if [[ $confirm_status -ne 0 ]]; then
		return "$confirm_status"
	fi

	: > "$ARCHINSTALL_LOG" || {
		error_box "Log Error" "Could not write the install log:\n\n$ARCHINSTALL_LOG"
		return 1
	}

	if (
		ARCHINSTALL_INSTALL_SUCCESS=false
		ARCHINSTALL_CLEANUP_ACTIVE=true
		trap 'cleanup_install EXIT' EXIT
		trap 'cleanup_install INT' INT

		log_line "Starting installation on $disk"
		if flag_enabled "$DEV_MODE"; then
			log_line "DEV_MODE enabled: SKIP_PARTITION=$SKIP_PARTITION SKIP_PACSTRAP=$SKIP_PACSTRAP SKIP_CHROOT=$SKIP_CHROOT"
		fi

		run_step "Unmounting any previous install target" cleanup_mounts || exit 1
		run_step "Checking internet connectivity" ping -c 1 archlinux.org || exit 1
		run_step "Refreshing pacman mirrors" reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist || exit 1

		if flag_enabled "$SKIP_PARTITION"; then
			log_line "Skipping partitioning and formatting because SKIP_PARTITION=$SKIP_PARTITION"
		else
			run_step "Wiping existing signatures on $disk" wipefs -a "$disk" || exit 1
			run_step "Creating a GPT partition table" parted -s "$disk" mklabel gpt || exit 1
			run_step "Creating the EFI system partition" parted -s "$disk" mkpart ESP fat32 1MiB 513MiB || exit 1
			run_step "Setting the EFI boot flag" parted -s "$disk" set 1 boot on || exit 1
			run_step "Setting the EFI ESP flag" parted -s "$disk" set 1 esp on || exit 1
			run_step "Creating the root partition" parted -s "$disk" mkpart ROOT ext4 513MiB 100% || exit 1
			run_step "Refreshing the kernel partition table" partprobe "$disk" || exit 1

			if command -v udevadm >/dev/null 2>&1; then
				run_step "Waiting for partition device nodes" udevadm settle || exit 1
			fi
		fi

		mapfile -t resolved_partitions < <(resolve_target_partitions "$disk") || exit 1
		efi_partition=${resolved_partitions[0]:-}
		root_partition=${resolved_partitions[1]:-}

		if [[ -z $efi_partition || -z $root_partition ]]; then
			error_box "Partition Detection Failed" "Could not resolve the EFI and root partitions for:\n\n$disk"
			exit 1
		fi

		set_state "EFI_PART" "$efi_partition" || exit 1
		set_state "ROOT_PART" "$root_partition" || exit 1

		if flag_enabled "$SKIP_PARTITION"; then
			log_line "Skipping filesystem creation because SKIP_PARTITION=$SKIP_PARTITION"
		else
			run_step "Formatting the EFI partition as FAT32" mkfs.fat -F32 "$efi_partition" || exit 1
			run_step "Formatting the root partition as ext4" mkfs.ext4 -F "$root_partition" || exit 1
		fi

		run_step "Mounting the root filesystem" mount "$root_partition" /mnt || exit 1
		run_step "Creating the EFI mount point" mkdir -p /mnt/boot || exit 1
		run_step "Mounting the EFI partition" mount "$efi_partition" /mnt/boot || exit 1

		if flag_enabled "$SKIP_PACSTRAP"; then
			log_line "Skipping pacstrap because SKIP_PACSTRAP=$SKIP_PACSTRAP"
			if [[ ! -d /mnt/etc ]]; then
				error_box "Pacstrap Skipped" "SKIP_PACSTRAP=true requires an existing system mounted at /mnt."
				exit 1
			fi
		else
			run_step_with_retry "Installing the base Arch Linux packages" 3 pacstrap /mnt base linux linux-firmware || exit 1
		fi

		run_shell_step "Generating fstab" 'mkdir -p /mnt/etc && : > /mnt/etc/fstab && genfstab -U /mnt >> /mnt/etc/fstab' || exit 1

		if flag_enabled "$SKIP_CHROOT"; then
			log_line "Skipping chroot configuration because SKIP_CHROOT=$SKIP_CHROOT"
		else
			root_partuuid="$(blkid -s PARTUUID -o value "$root_partition" 2>> "$ARCHINSTALL_LOG" || true)"
			if [[ -z $root_partuuid ]]; then
				error_box "Bootloader Error" "Could not determine the root PARTUUID for:\n\n$root_partition"
				exit 1
			fi

			run_chroot_configuration "$root_partuuid" || exit 1
		fi

		ARCHINSTALL_INSTALL_SUCCESS=true
		ARCHINSTALL_CLEANUP_ACTIVE=false
		log_line "Installation completed successfully"
		exit 0
	); then
		msg "Installation Complete" "A bootable Arch Linux system was prepared successfully.\n\nMounted target:\n/mnt\n\nLog file:\n$ARCHINSTALL_LOG"
		return 0
	else
		install_status=$?
	fi

	return "$install_status"
}