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
INSTALL_UI_MODE=${INSTALL_UI_MODE:-plain}

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

install_ui_uses_dialog() {
	[[ ${INSTALL_UI_MODE:-plain} == "dialog" ]]
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

print_install_info() {
	printf '[*] %s\n' "$1"
}

print_install_error() {
	printf '[!] %s\n' "$1" >&2
}

run_logged_command() {
	if install_ui_uses_dialog; then
		"$@" >> "$ARCHINSTALL_LOG" 2>&1
		return $?
	fi

	"$@" 2>&1 | tee -a "$ARCHINSTALL_LOG"
}

run_logged_shell_command() {
	local command_string=${1:?command string is required}

	if install_ui_uses_dialog; then
		bash -lc "$command_string" >> "$ARCHINSTALL_LOG" 2>&1
		return $?
	fi

	bash -lc "$command_string" 2>&1 | tee -a "$ARCHINSTALL_LOG"
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
	print_install_error "Installation failed during: $step"
	if [[ -n $excerpt ]]; then
		printf '%s\n' "$excerpt" >&2
	fi
	print_install_error "Full log: $ARCHINSTALL_LOG"
}

run_step() {
	local step=${1:?step description is required}

	shift
	install_ui_uses_dialog || print_install_info "$step"
	log_line "$step"

	if run_logged_command "$@"; then
		return 0
	fi

	show_install_error "$step"
	return 1
}

run_shell_step() {
	local step=${1:?step description is required}
	local command_string=${2:?command string is required}

	install_ui_uses_dialog || print_install_info "$step"
	log_line "$step"

	if run_logged_shell_command "$command_string"; then
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
		install_ui_uses_dialog || print_install_info "$step (attempt $attempt/$max_attempts)"
		log_line "$step (attempt $attempt/$max_attempts)"

		if run_logged_command "$@"; then
			return 0
		fi

		if (( attempt == max_attempts )); then
			show_install_error "$step"
			return 1
		fi

		attempt=$((attempt + 1))
	done
}

run_install_gauge() {
	local root_partition=${1:?root partition is required}
	local root_partuuid=""
	local gauge_status=0
	local -a gauge_pipe_status=()

	if (
		echo 10
		echo "# Preparing install..."

		if flag_enabled "$SKIP_PACSTRAP"; then
			log_line "Skipping pacstrap because SKIP_PACSTRAP=$SKIP_PACSTRAP"
			if [[ ! -d /mnt/etc ]]; then
				print_install_error "SKIP_PACSTRAP=true requires an existing system mounted at /mnt."
				exit 1
			fi
		else
			echo 30
			echo "# Installing base system..."
			run_step_with_retry "Installing the base Arch Linux packages" 3 pacstrap /mnt base linux linux-firmware || exit 1
		fi

		echo 80
		echo "# Generating fstab..."
		run_shell_step "Generating fstab" 'mkdir -p /mnt/etc && : > /mnt/etc/fstab && genfstab -U /mnt >> /mnt/etc/fstab' || exit 1

		if flag_enabled "$SKIP_CHROOT"; then
			log_line "Skipping chroot configuration because SKIP_CHROOT=$SKIP_CHROOT"
		else
			root_partuuid="$(blkid -s PARTUUID -o value "$root_partition" 2>> "$ARCHINSTALL_LOG" || true)"
			if [[ -z $root_partuuid ]]; then
				print_install_error "Could not determine the root PARTUUID for: $root_partition"
				exit 1
			fi

			echo 90
			echo "# Configuring system..."
			run_chroot_configuration "$root_partuuid" || exit 1
		fi

		echo 100
		echo "# Done"
	) | dialog --title "ArchInstall Framework" --gauge "Installing system..." 10 70 0
	gauge_pipe_status=("${PIPESTATUS[@]}")
	gauge_status=${gauge_pipe_status[0]:-1}

	if [[ $gauge_status -eq 0 ]]; then
		return 0
	fi

	show_install_error "Bootable system installation"
	return "$gauge_status"
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
		print_install_error "Expected partitions were not found: $efi_partition $root_partition"
		return 1
	fi

	printf '%s\n%s\n' "$efi_partition" "$root_partition"
}

run_chroot_configuration() {
	local root_partuuid=${1:?root PARTUUID is required}

	install_ui_uses_dialog || print_install_info "Configuring the new system and installing systemd-boot"
	log_line "Configuring the target system inside chroot"

	if install_ui_uses_dialog; then
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
	else
		if arch-chroot /mnt /bin/bash <<EOF 2>&1 | tee -a "$ARCHINSTALL_LOG"
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
	fi

	show_install_error "Configuring the new system"
	return 1
}

install_base_system() {
	local disk=""
	local efi_partition=""
	local root_partition=""
	local root_partuuid=""
	local install_status=0
	local -a resolved_partitions=()

	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		print_install_error "Run the installer as root from the Arch Linux live environment."
		return 1
	fi

	require_commands || return 1

	disk="$(get_state "DISK" 2>/dev/null || true)"
	if [[ -z $disk ]]; then
		print_install_error "Select a target disk before starting the installation."
		return 1
	fi

	if [[ ! -b $disk ]]; then
		print_install_error "The saved disk does not exist anymore: $disk"
		return 1
	fi

	: > "$ARCHINSTALL_LOG" || {
		print_install_error "Could not write the install log: $ARCHINSTALL_LOG"
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
			print_install_error "Could not resolve the EFI and root partitions for: $disk"
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

		if install_ui_uses_dialog; then
			run_install_gauge "$root_partition" || exit 1
		else
			if flag_enabled "$SKIP_PACSTRAP"; then
				log_line "Skipping pacstrap because SKIP_PACSTRAP=$SKIP_PACSTRAP"
				if [[ ! -d /mnt/etc ]]; then
					print_install_error "SKIP_PACSTRAP=true requires an existing system mounted at /mnt."
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
					print_install_error "Could not determine the root PARTUUID for: $root_partition"
					exit 1
				fi

				run_chroot_configuration "$root_partuuid" || exit 1
			fi
		fi

		ARCHINSTALL_INSTALL_SUCCESS=true
		ARCHINSTALL_CLEANUP_ACTIVE=false
		log_line "Installation completed successfully"
		exit 0
	); then
		return 0
	else
		install_status=$?
	fi

	return "$install_status"
}