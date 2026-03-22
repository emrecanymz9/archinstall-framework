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
# shellcheck source=installer/modules/bootloader.sh
source "$SCRIPT_DIR/modules/bootloader.sh"
# shellcheck source=installer/modules/network.sh
source "$SCRIPT_DIR/modules/network.sh"
# shellcheck source=installer/modules/desktop.sh
source "$SCRIPT_DIR/modules/desktop.sh"

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

render_command() {
	local rendered_command=""

	printf -v rendered_command '%q ' "$@"
	printf '%s\n' "${rendered_command% }"
}

build_pacstrap_package_list() {
	local boot_mode=${1:?boot mode is required}
	local filesystem=${2:?filesystem is required}
	local enable_zram=${3:?zram flag is required}
	local -n package_ref=${4:?package reference is required}
	local desktop_profile=${5:-none}
	local display_manager=${6:-none}
	local -a desktop_packages=()

	package_ref=(base linux linux-firmware sudo networkmanager iptables-nft mkinitcpio)
	if [[ $filesystem == "btrfs" ]]; then
		package_ref+=(btrfs-progs)
	fi
	if flag_enabled "$enable_zram"; then
		package_ref+=(zram-generator)
	fi
	if [[ $boot_mode == "bios" ]]; then
		package_ref+=(grub)
	fi
	if desktop_profile_packages "$desktop_profile" "$display_manager" desktop_packages; then
		if [[ ${#desktop_packages[@]} -gt 0 ]]; then
			package_ref+=("${desktop_packages[@]}")
		fi
	fi
}

normalize_filesystem() {
	case ${1:-ext4} in
		ext4|btrfs)
			printf '%s\n' "$1"
			return 0
			;;
		*)
			printf 'ext4\n'
			return 0
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
	local boot_mode=""
	local filesystem=""

	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || detect_boot_mode 2>/dev/null || printf 'uefi')"
	filesystem="$(normalize_filesystem "$(get_state "FILESYSTEM" 2>/dev/null || printf 'ext4')")"

	for cmd in dialog lsblk wipefs parted partprobe mkfs.ext4 mount umount pacman pacstrap ping blkid arch-chroot tee tail findmnt; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done

	if [[ $boot_mode == "uefi" ]]; then
		for cmd in mkfs.fat bootctl; do
			command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
		done
	else
		for cmd in grub-install grub-mkconfig; do
			command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
		done
	fi

	if [[ $filesystem == "btrfs" ]]; then
		for cmd in mkfs.btrfs btrfs; do
			command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
		done
	fi

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

sanitize_stream() {
	if command -v stdbuf >/dev/null 2>&1; then
		stdbuf -oL tr -cd '\11\12\15\40-\176'
		return
	fi

	tr -cd '\11\12\15\40-\176'
}

print_install_info() {
	printf '[*] %s\n' "$1"
}

print_install_error() {
	printf '[!] %s\n' "$1" >&2
}

run_logged_command() {
	log_line "Command: $(render_command "$@")"

	if install_ui_uses_dialog; then
		"$@" 2>&1 | sanitize_stream | tee -a "$ARCHINSTALL_LOG" >/dev/null
		return $?
	fi

	"$@" 2>&1 | sanitize_stream | tee -a "$ARCHINSTALL_LOG"
}

run_logged_shell_command() {
	local command_string=${1:?command string is required}

	log_line "Command: bash -lc $command_string"

	if install_ui_uses_dialog; then
		bash -lc "$command_string" 2>&1 | sanitize_stream | tee -a "$ARCHINSTALL_LOG" >/dev/null
		return $?
	fi

	bash -lc "$command_string" 2>&1 | sanitize_stream | tee -a "$ARCHINSTALL_LOG"
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

	excerpt="$(tail -n 20 "$ARCHINSTALL_LOG" 2>/dev/null || true)"
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
	log_line "[STEP] $step"

	if run_logged_command "$@"; then
		log_line "[ OK ] $step"
		return 0
	fi

	log_line "[FAIL] $step"
	show_install_error "$step"
	return 1
}

run_shell_step() {
	local step=${1:?step description is required}
	local command_string=${2:?command string is required}

	install_ui_uses_dialog || print_install_info "$step"
	log_line "[STEP] $step"

	if run_logged_shell_command "$command_string"; then
		log_line "[ OK ] $step"
		return 0
	fi

	log_line "[FAIL] $step"
	show_install_error "$step"
	return 1
}

run_optional_step() {
	local step=${1:?step description is required}

	shift
	install_ui_uses_dialog || print_install_info "$step"
	log_line "[STEP] $step"

	if run_logged_command "$@"; then
		log_line "[ OK ] $step"
		return 0
	fi

	log_line "[WARN] Non-critical step failed: $step"
	return 0
}

run_optional_shell_step() {
	local step=${1:?step description is required}
	local command_string=${2:?command string is required}

	install_ui_uses_dialog || print_install_info "$step"
	log_line "[STEP] $step"

	if run_logged_shell_command "$command_string"; then
		log_line "[ OK ] $step"
		return 0
	fi

	log_line "[WARN] Non-critical shell step failed: $step"
	return 0
}

run_step_with_retry() {
	local step=${1:?step description is required}
	local max_attempts=${2:?max attempts is required}
	local attempt=1

	shift 2

	while (( attempt <= max_attempts )); do
		install_ui_uses_dialog || print_install_info "$step (attempt $attempt/$max_attempts)"
		log_line "[STEP] $step (attempt $attempt/$max_attempts)"

		if run_logged_command "$@"; then
			log_line "[ OK ] $step"
			return 0
		fi

		if (( attempt == max_attempts )); then
			log_line "[FAIL] $step"
			show_install_error "$step"
			return 1
		fi

		log_line "[WARN] Retrying: $step"
		attempt=$((attempt + 1))
	done
}

run_pacstrap_install() {
	local -a packages=("$@")

	run_step_with_retry "Installing the base Arch Linux packages" 3 pacstrap -K /mnt --noconfirm --needed --overwrite='*' "${packages[@]}"
}

get_partition_uuid() {
	local partition=${1:?partition is required}
	local uuid=""

	uuid="$(blkid -s UUID -o value "$partition" 2>> "$ARCHINSTALL_LOG" || true)"
	if [[ -z $uuid ]]; then
		print_install_error "Could not determine the UUID for: $partition"
		return 1
	fi

	printf '%s\n' "$uuid"
}

log_partition_metadata() {
	local root_partition=${1:?root partition is required}
	local efi_partition=${2-}

	if [[ -n $efi_partition ]]; then
		run_optional_step "Capturing block metadata" blkid "$efi_partition" "$root_partition"
		return 0
	fi

	run_optional_step "Capturing block metadata" blkid "$root_partition"
	return 0
}

log_mounted_filesystems() {
	local filesystem=${1:?filesystem is required}

	run_optional_step "Recording root mount details" findmnt -no TARGET,SOURCE,OPTIONS /mnt
	if [[ $filesystem == "btrfs" ]]; then
		run_optional_step "Recording home mount details" findmnt -no TARGET,SOURCE,OPTIONS /mnt/home
	fi
}

write_target_fstab() {
	local filesystem=${1:?filesystem is required}
	local root_partition=${2:?root partition is required}
	local efi_partition=${3-}
	local root_uuid=""
	local efi_uuid=""
	local fstab_path=/mnt/etc/fstab
	local root_line=""
	local home_line=""
	local efi_line=""

	root_uuid="$(get_partition_uuid "$root_partition")" || return 1
	if [[ -n $efi_partition ]]; then
		efi_uuid="$(get_partition_uuid "$efi_partition")" || return 1
	fi

	case $filesystem in
		ext4)
			root_line="UUID=$root_uuid / ext4 defaults,noatime 0 1"
			;;
		btrfs)
			root_line="UUID=$root_uuid / btrfs subvol=@,compress=zstd 0 0"
			home_line="UUID=$root_uuid /home btrfs subvol=@home,compress=zstd 0 0"
			;;
		*)
			print_install_error "Unsupported filesystem for fstab generation: $filesystem"
			return 1
			;;
	esac

	if [[ -n $efi_uuid ]]; then
		efi_line="UUID=$efi_uuid /boot vfat umask=0077 0 2"
	fi

	run_shell_step "Generating fstab" "mkdir -p /mnt/etc && cat > '$fstab_path' <<'EOT'
$root_line
$home_line
$efi_line
EOT"
	local fstab_status=$?
	if [[ $fstab_status -ne 0 ]]; then
		return "$fstab_status"
	fi

	log_line "[DEBUG] Generated fstab:"
	if [[ -f $fstab_path ]]; then
		sanitize_stream < "$fstab_path" >> "$ARCHINSTALL_LOG"
	fi

	return 0
}

format_root_filesystem() {
	local filesystem=${1:?filesystem is required}
	local root_partition=${2:?root partition is required}

	case $filesystem in
		ext4)
			run_step "Formatting the root partition as ext4" mkfs.ext4 -F "$root_partition"
			;;
		btrfs)
			run_step "Formatting the root partition as btrfs" mkfs.btrfs -f "$root_partition"
			;;
		*)
			print_install_error "Unsupported filesystem: $filesystem"
			return 1
			;;
	esac
}

mount_root_filesystem() {
	local filesystem=${1:?filesystem is required}
	local root_partition=${2:?root partition is required}

	case $filesystem in
		ext4)
			run_step "Mounting the root filesystem" mount "$root_partition" /mnt
			;;
		btrfs)
			run_step "Mounting btrfs volume for subvolume creation" mount "$root_partition" /mnt || return 1
			if [[ ! -d /mnt/@ ]]; then
				run_step "Creating btrfs root subvolume" btrfs subvolume create /mnt/@ || return 1
			else
				log_line "[ OK ] Reusing existing btrfs root subvolume @"
			fi
			if [[ ! -d /mnt/@home ]]; then
				run_step "Creating btrfs home subvolume" btrfs subvolume create /mnt/@home || return 1
			else
				log_line "[ OK ] Reusing existing btrfs home subvolume @home"
			fi
			run_step "Unmounting temporary btrfs mount" umount /mnt || return 1
			run_step "Mounting the btrfs root subvolume" mount -o compress=zstd,subvol=@ "$root_partition" /mnt || return 1
			run_step "Creating the home mount point" mkdir -p /mnt/home || return 1
			run_step "Mounting the btrfs home subvolume" mount -o compress=zstd,subvol=@home "$root_partition" /mnt/home || return 1
			run_step "Recording mounted btrfs subvolumes" findmnt -no TARGET,SOURCE,OPTIONS /mnt /mnt/home
			;;
		*)
			print_install_error "Unsupported filesystem: $filesystem"
			return 1
			;;
	esac
}

resolve_target_partitions() {
	local disk=${1:?disk is required}
	local boot_mode=${2:?boot mode is required}
	local efi_partition=""
	local root_partition=""

	efi_partition="$(get_state "EFI_PART" 2>/dev/null || true)"
	root_partition="$(get_state "ROOT_PART" 2>/dev/null || true)"

	if [[ $boot_mode == "uefi" ]]; then
		[[ -n $efi_partition ]] || efi_partition="$(partition_path "$disk" 1)"
		[[ -n $root_partition ]] || root_partition="$(partition_path "$disk" 2)"
	else
		efi_partition="-"
		[[ -n $root_partition ]] || root_partition="$(partition_path "$disk" 1)"
	fi

	if [[ $boot_mode == "uefi" && ! -b $efi_partition ]]; then
		print_install_error "Expected EFI partition was not found: $efi_partition"
		return 1
	fi

	if [[ ! -b $root_partition ]]; then
		print_install_error "Expected partitions were not found: $efi_partition $root_partition"
		return 1
	fi

	printf '%s\n%s\n' "$efi_partition" "$root_partition"
}

build_chroot_script() {
	local boot_mode=${1:?boot mode is required}
	local disk=${2:?disk is required}
	local root_uuid=${3:?root UUID is required}
	local filesystem=${4:?filesystem is required}
	local enable_zram=${5:?zram flag is required}
	local desktop_profile=${6:-none}
	local display_manager=${7:-none}
	local hostname=""
	local timezone=""
	local locale=""
	local keymap=""
	local username=""
	local user_password=${INSTALL_USER_PASSWORD:-}
	local root_password=${INSTALL_ROOT_PASSWORD:-}
	local quoted_boot_mode=""
	local quoted_disk=""
	local quoted_root_uuid=""
	local quoted_hostname=""
	local quoted_timezone=""
	local quoted_locale=""
	local quoted_keymap=""
	local quoted_username=""
	local quoted_user_password=""
	local quoted_root_password=""
	local quoted_filesystem=""
	local quoted_enable_zram=""
	local quoted_desktop_profile=""
	local quoted_display_manager=""

	hostname="$(get_state "HOSTNAME" 2>/dev/null || printf 'archlinux')"
	timezone="$(get_state "TIMEZONE" 2>/dev/null || printf 'Europe/Istanbul')"
	locale="$(get_state "LOCALE" 2>/dev/null || printf 'en_US.UTF-8')"
	keymap="$(get_state "KEYMAP" 2>/dev/null || printf 'us')"
	username="$(get_state "USERNAME" 2>/dev/null || printf 'archuser')"

	if [[ -z $user_password ]]; then
		print_install_error "The installer user password is not set. Configure the install profile before starting."
		return 1
	fi
	if [[ -z $root_password ]]; then
		print_install_error "The root password is not set. Configure the install profile before starting."
		return 1
	fi

	printf -v quoted_boot_mode '%q' "$boot_mode"
	printf -v quoted_disk '%q' "$disk"
	printf -v quoted_root_uuid '%q' "$root_uuid"
	printf -v quoted_hostname '%q' "$hostname"
	printf -v quoted_timezone '%q' "$timezone"
	printf -v quoted_locale '%q' "$locale"
	printf -v quoted_keymap '%q' "$keymap"
	printf -v quoted_username '%q' "$username"
	printf -v quoted_user_password '%q' "$user_password"
	printf -v quoted_root_password '%q' "$root_password"
	printf -v quoted_filesystem '%q' "$filesystem"
	printf -v quoted_enable_zram '%q' "$enable_zram"
	printf -v quoted_desktop_profile '%q' "$desktop_profile"
	printf -v quoted_display_manager '%q' "$display_manager"

	cat <<EOF
set -euo pipefail

BOOT_MODE=$quoted_boot_mode
TARGET_DISK=$quoted_disk
ROOT_UUID=$quoted_root_uuid
TARGET_HOSTNAME=$quoted_hostname
TARGET_TIMEZONE=$quoted_timezone
TARGET_LOCALE=$quoted_locale
TARGET_KEYMAP=$quoted_keymap
TARGET_USERNAME=$quoted_username
TARGET_USER_PASSWORD=$quoted_user_password
TARGET_ROOT_PASSWORD=$quoted_root_password
TARGET_FILESYSTEM=$quoted_filesystem
TARGET_ENABLE_ZRAM=$quoted_enable_zram
TARGET_DESKTOP_PROFILE=$quoted_desktop_profile
TARGET_DISPLAY_MANAGER=$quoted_display_manager

echo "[DEBUG] Applying mkinitcpio hooks"
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf

ln -sf "/usr/share/zoneinfo/\$TARGET_TIMEZONE" /etc/localtime
hwclock --systohc

if ! grep -qx "\$TARGET_LOCALE UTF-8" /etc/locale.gen; then
	echo "\$TARGET_LOCALE UTF-8" >> /etc/locale.gen
fi
locale-gen
printf '%s\n' "LANG=\$TARGET_LOCALE" > /etc/locale.conf
printf '%s\n' "KEYMAP=\$TARGET_KEYMAP" > /etc/vconsole.conf

printf '%s\n' "\$TARGET_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOT
127.0.0.1 localhost
::1       localhost
127.0.1.1 \$TARGET_HOSTNAME.localdomain \$TARGET_HOSTNAME
EOT

if ! id -u "\$TARGET_USERNAME" >/dev/null 2>&1; then
	useradd -m -G wheel -s /bin/bash "\$TARGET_USERNAME"
fi
echo "\$TARGET_USERNAME:\$TARGET_USER_PASSWORD" | chpasswd
echo "root:\$TARGET_ROOT_PASSWORD" | chpasswd

if grep -q '^# %wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
	sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
elif ! grep -q '^%wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
	echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
fi

systemctl enable NetworkManager

if [[ \$TARGET_ENABLE_ZRAM == "true" ]]; then
	mkdir -p /etc/systemd
	cat > /etc/systemd/zram-generator.conf <<'EOT'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOT
fi

mkinitcpio -P

if [[ \$TARGET_DESKTOP_PROFILE == "kde" ]]; then
	systemctl enable bluetooth
	install -d -m 0755 /etc/systemd/user/default.target.wants
	ln -sf /usr/lib/systemd/user/pipewire.service /etc/systemd/user/default.target.wants/pipewire.service
	ln -sf /usr/lib/systemd/user/pipewire-pulse.service /etc/systemd/user/default.target.wants/pipewire-pulse.service
	ln -sf /usr/lib/systemd/user/wireplumber.service /etc/systemd/user/default.target.wants/wireplumber.service

	case \$TARGET_DISPLAY_MANAGER in
		sddm)
			systemctl enable sddm
			;;
		greetd)
			install -d -m 0755 /etc/greetd
			install -d -m 0755 /etc/qtgreet
			cat > /etc/qtgreet/sway-config <<'EOT'
exec "qtgreet; swaymsg exit"
include /etc/sway/config.d/*
EOT
			cat > /etc/greetd/config.toml <<'EOT'
[terminal]
vt = 1

[default_session]
command = "sway --config /etc/qtgreet/sway-config"
user = "greeter"
EOT
			if [[ ! -x /usr/bin/qtgreet ]]; then
				echo "[WARN] qtgreet was not found in the target system. Install the AUR package greetd-qtgreet to activate this greetd path."
			fi
			systemctl enable greetd
			;;
	esac
fi

if [[ \$BOOT_MODE == "uefi" ]]; then
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
options root=UUID=\$ROOT_UUID rw$( [[ $filesystem == "btrfs" ]] && printf ' rootfstype=btrfs rootflags=subvol=@,compress=zstd' )
EOT

	echo "[DEBUG] systemd-boot entry"
	cat /boot/loader/entries/arch.conf
else
	grub_cmdline="root=UUID=\$ROOT_UUID"
	if [[ \$TARGET_FILESYSTEM == "btrfs" ]]; then
		grub_cmdline="\$grub_cmdline rootflags=subvol=@,compress=zstd"
	fi
	if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
		sed -i "s#^GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX=\"\$grub_cmdline\"#" /etc/default/grub
	else
		printf '%s\n' "GRUB_CMDLINE_LINUX=\"\$grub_cmdline\"" >> /etc/default/grub
	fi
	if grep -q '^GRUB_DISABLE_LINUX_UUID=' /etc/default/grub; then
		sed -i 's/^GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
	else
		echo 'GRUB_DISABLE_LINUX_UUID=true' >> /etc/default/grub
	fi

	grub-install --target=i386-pc "\$TARGET_DISK"
	grub-mkconfig -o /boot/grub/grub.cfg

	echo "[DEBUG] /etc/default/grub"
	cat /etc/default/grub
	echo "[DEBUG] Generated grub.cfg linux lines"
	grep -n 'linux.*/vmlinuz-linux' /boot/grub/grub.cfg || true
fi
EOF
}

run_chroot_configuration() {
	local boot_mode=${1:?boot mode is required}
	local disk=${2:?disk is required}
	local root_uuid=${3:?root UUID is required}
	local filesystem=${4:?filesystem is required}
	local enable_zram=${5:?zram flag is required}
	local desktop_profile=${6:-none}
	local display_manager=${7:-none}

	install_ui_uses_dialog || print_install_info "Configuring the new system and installing the bootloader"
	log_line "[STEP] Configuring the target system inside chroot"

	if install_ui_uses_dialog; then
		if build_chroot_script "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$enable_zram" "$desktop_profile" "$display_manager" | arch-chroot /mnt /bin/bash >> "$ARCHINSTALL_LOG" 2>&1
		then
			log_line "[ OK ] Configuring the target system inside chroot"
			return 0
		fi
	else
		if build_chroot_script "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$enable_zram" "$desktop_profile" "$display_manager" | arch-chroot /mnt /bin/bash 2>&1 | tee -a "$ARCHINSTALL_LOG"
		then
			log_line "[ OK ] Configuring the target system inside chroot"
			return 0
		fi
	fi

	log_line "[FAIL] Configuring the target system inside chroot"
	show_install_error "Configuring the new system"
	return 1
}

run_install() {
	local disk=""
	local efi_partition=""
	local root_partition=""
	local root_uuid=""
	local boot_mode=""
	local filesystem=""
	local enable_zram=""
	local desktop_profile=""
	local display_manager=""
	local install_status=0
	local -a resolved_partitions=()
	local -a pacstrap_packages=()

	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		print_install_error "Run the installer as root from the Arch Linux live environment."
		return 1
	fi

	require_commands || return 1

	disk="$(get_state "DISK" 2>/dev/null || true)"
	boot_mode="$(get_state "BOOT_MODE" 2>/dev/null || true)"
	filesystem="$(normalize_filesystem "$(get_state "FILESYSTEM" 2>/dev/null || printf 'ext4')")"
	enable_zram="$(get_state "ENABLE_ZRAM" 2>/dev/null || printf 'false')"
	desktop_profile="$(get_state "DESKTOP_PROFILE" 2>/dev/null || printf 'none')"
	display_manager="$(get_state "DISPLAY_MANAGER" 2>/dev/null || printf 'none')"
	[[ -n $boot_mode ]] || boot_mode="$(detect_boot_mode)"
	case $boot_mode in
		uefi|bios)
			;;
		*)
			print_install_error "Unsupported boot mode: $boot_mode"
			return 1
			;;
	esac

	if [[ -z $disk ]]; then
		print_install_error "Select a target disk before starting the installation."
		return 1
	fi

	if [[ ! -b $disk ]]; then
		print_install_error "The saved disk does not exist anymore: $disk"
		return 1
	fi

	build_pacstrap_package_list "$boot_mode" "$filesystem" "$enable_zram" pacstrap_packages "$desktop_profile" "$display_manager"

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
		log_line "Boot mode: $boot_mode"
		log_line "Filesystem: $filesystem"
		log_line "Zram: $enable_zram"
		log_line "Desktop profile: $desktop_profile"
		log_line "Display manager: $display_manager"
		if flag_enabled "$DEV_MODE"; then
			log_line "DEV_MODE enabled: SKIP_PARTITION=$SKIP_PARTITION SKIP_PACSTRAP=$SKIP_PACSTRAP SKIP_CHROOT=$SKIP_CHROOT"
		fi

		run_step "Unmounting any previous install target" cleanup_mounts || exit 1
		run_optional_step "Checking internet connectivity" ping -c 1 archlinux.org
		initialize_pacman_environment || exit 1

		if flag_enabled "$SKIP_PARTITION"; then
			log_line "Skipping partitioning and formatting because SKIP_PARTITION=$SKIP_PARTITION"
		else
			run_step "Wiping existing signatures on $disk" wipefs -a "$disk" || exit 1
			if [[ $boot_mode == "uefi" ]]; then
				run_step "Creating a GPT partition table" parted -s "$disk" mklabel gpt || exit 1
				run_step "Creating the EFI system partition" parted -s "$disk" mkpart ESP fat32 1MiB 513MiB || exit 1
				run_step "Setting the EFI boot flag" parted -s "$disk" set 1 boot on || exit 1
				run_step "Setting the EFI ESP flag" parted -s "$disk" set 1 esp on || exit 1
				run_step "Creating the root partition" parted -s "$disk" mkpart ROOT ext4 513MiB 100% || exit 1
			else
				run_step "Creating an MBR partition table" parted -s "$disk" mklabel msdos || exit 1
				run_step "Creating the root partition" parted -s "$disk" mkpart primary ext4 1MiB 100% || exit 1
				run_step "Marking the root partition bootable" parted -s "$disk" set 1 boot on || exit 1
			fi
			run_step "Refreshing the kernel partition table" partprobe "$disk" || exit 1

			if command -v udevadm >/dev/null 2>&1; then
				run_step "Waiting for partition device nodes" udevadm settle || exit 1
			fi
		fi

		mapfile -t resolved_partitions < <(resolve_target_partitions "$disk" "$boot_mode") || exit 1
		efi_partition=${resolved_partitions[0]:-}
		root_partition=${resolved_partitions[1]:-}
		[[ $efi_partition == "-" ]] && efi_partition=""

		if [[ -z $root_partition ]]; then
			print_install_error "Could not resolve the target partitions for: $disk"
			exit 1
		fi
		if [[ $boot_mode == "uefi" && -z $efi_partition ]]; then
			print_install_error "Could not resolve the EFI partition for: $disk"
			exit 1
		fi

		if [[ -n $efi_partition ]]; then
			set_state "EFI_PART" "$efi_partition" || exit 1
		else
			unset_state "EFI_PART" || exit 1
		fi
		set_state "BOOT_MODE" "$boot_mode" || exit 1
		set_state "ROOT_PART" "$root_partition" || exit 1

		if flag_enabled "$SKIP_PARTITION"; then
			log_line "Skipping filesystem creation because SKIP_PARTITION=$SKIP_PARTITION"
		else
			if [[ $boot_mode == "uefi" ]]; then
				run_step "Formatting the EFI partition as FAT32" mkfs.fat -F32 "$efi_partition" || exit 1
			fi
			format_root_filesystem "$filesystem" "$root_partition" || exit 1
		fi

		mount_root_filesystem "$filesystem" "$root_partition" || exit 1
		if [[ $boot_mode == "uefi" ]]; then
			run_step "Creating the EFI mount point" mkdir -p /mnt/boot || exit 1
			run_step "Mounting the EFI partition" mount "$efi_partition" /mnt/boot || exit 1
		fi
		log_partition_metadata "$root_partition" "$efi_partition"
		log_mounted_filesystems "$filesystem"

		if flag_enabled "$SKIP_PACSTRAP"; then
			log_line "Skipping pacstrap because SKIP_PACSTRAP=$SKIP_PACSTRAP"
			if [[ ! -d /mnt/etc ]]; then
				print_install_error "SKIP_PACSTRAP=true requires an existing system mounted at /mnt."
				exit 1
			fi
		else
			run_pacstrap_install "${pacstrap_packages[@]}" || exit 1
		fi

		write_target_fstab "$filesystem" "$root_partition" "$efi_partition" || exit 1

		if flag_enabled "$SKIP_CHROOT"; then
			log_line "Skipping chroot configuration because SKIP_CHROOT=$SKIP_CHROOT"
		else
			root_uuid="$(get_partition_uuid "$root_partition")" || exit 1
			run_chroot_configuration "$boot_mode" "$disk" "$root_uuid" "$filesystem" "$enable_zram" "$desktop_profile" "$display_manager" || exit 1
		fi

		ARCHINSTALL_INSTALL_SUCCESS=true
		ARCHINSTALL_CLEANUP_ACTIVE=false
		log_line "[ OK ] Installation completed successfully"
		log_line "Close the log view to continue to the final menu."
		exit 0
	); then
		return 0
	else
		install_status=$?
	fi

	return "$install_status"
}
