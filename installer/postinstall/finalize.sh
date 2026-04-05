#!/usr/bin/env bash

postinstall_generate_fstab() {
	write_target_fstab "$@"
}

postinstall_finalize_chroot_snippet() {
	cat <<'EOF'
log_chroot_step "Validating required chroot variables"
if [[ -z ${TARGET_LOCALE:-} ]]; then
	echo "[FAIL] TARGET_LOCALE is empty; cannot configure locale in chroot"
	exit 1
fi
if [[ -z ${TARGET_USERNAME:-} ]]; then
	echo "[FAIL] TARGET_USERNAME is empty; cannot create user in chroot"
	exit 1
fi
if [[ ! ${TARGET_USERNAME} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
	echo "[FAIL] TARGET_USERNAME '${TARGET_USERNAME}' is not a valid Linux username"
	exit 1
fi

log_chroot_step "Configuring mkinitcpio hooks"
if [[ ! -f /etc/mkinitcpio.conf ]]; then
	echo "[FAIL] /etc/mkinitcpio.conf is missing inside the target chroot"
	exit 1
fi
echo "[DEBUG] Preparing to update /etc/mkinitcpio.conf inside chroot"
echo "[DEBUG] Applying mkinitcpio hooks"
sed -i "s/^HOOKS=.*/HOOKS=($TARGET_MKINITCPIO_HOOKS)/" /etc/mkinitcpio.conf

log_chroot_step "Configuring timezone"
ln -sf "/usr/share/zoneinfo/$TARGET_TIMEZONE" /etc/localtime
hwclock --systohc

log_chroot_step "Configuring locale"
if ! grep -qx "$TARGET_LOCALE UTF-8" /etc/locale.gen; then
	echo "$TARGET_LOCALE UTF-8" >> /etc/locale.gen
fi
locale-gen
printf '%s\n' "LANG=$TARGET_LOCALE" > /etc/locale.conf
printf '%s\n' "KEYMAP=$TARGET_KEYMAP" > /etc/vconsole.conf

log_chroot_step "Configuring hostname and hosts"
printf '%s\n' "$TARGET_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<'EOT'
127.0.0.1 localhost
::1       localhost
127.0.1.1 TARGET_HOSTNAME.localdomain TARGET_HOSTNAME
EOT
sed -i "s/TARGET_HOSTNAME/$TARGET_HOSTNAME/g" /etc/hosts

log_chroot_step "Creating user accounts and setting passwords"
if ! id -u "$TARGET_USERNAME" >/dev/null 2>&1; then
	useradd -m -G wheel -s /bin/bash "$TARGET_USERNAME"
fi
if ! id -u "$TARGET_USERNAME" >/dev/null 2>&1; then
	echo "[FAIL] useradd did not create user '$TARGET_USERNAME'"
	exit 1
fi
if [[ -n $TARGET_USER_PASSWORD ]]; then
	if ! echo "$TARGET_USERNAME:$TARGET_USER_PASSWORD" | chpasswd; then
		echo "[FAIL] chpasswd failed for user '$TARGET_USERNAME'"
		exit 1
	fi
else
	passwd -d "$TARGET_USERNAME"
	echo "[INFO] No password set for $TARGET_USERNAME; password entry cleared"
fi
if [[ -n $TARGET_ROOT_PASSWORD ]]; then
	if ! echo "root:$TARGET_ROOT_PASSWORD" | chpasswd; then
		echo "[FAIL] chpasswd failed for root"
		exit 1
	fi
else
	passwd -d root
	echo "[INFO] No password set for root; password entry cleared"
fi

log_chroot_step "Configuring sudo permissions"
if grep -q '^# %wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
	sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
elif ! grep -q '^%wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
	echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
fi
EOF
}
