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

set_account_password() {
	local account_name=${1:?account name is required}
	local account_password=${2-}
	local status=0
	local stderr_log="/tmp/archinstall-password-${account_name}.stderr"

	echo "[DEBUG] Preparing password operation for account: $account_name"
	if [[ -n $account_password ]]; then
		echo "[DEBUG] Applying password with chpasswd for account: $account_name"
		: > "$stderr_log"
		echo "$account_name:$account_password" | chpasswd 2>"$stderr_log"
		status=$?
		echo "[DEBUG] chpasswd exit code for $account_name: $status"
		if [[ -s $stderr_log ]]; then
			while IFS= read -r line; do
				echo "[DEBUG] chpasswd stderr ($account_name): $line"
			done < "$stderr_log"
		fi
		rm -f "$stderr_log"
		if [[ $status -ne 0 ]]; then
			echo "[FAIL] chpasswd failed for account: $account_name"
			return "$status"
		fi
		echo "[DEBUG] Password applied successfully for account: $account_name"
		return 0
	fi

		: > "$stderr_log"
		passwd -d "$account_name" 2>"$stderr_log"
	passwd -d "$account_name"
	status=$?
		if [[ -s $stderr_log ]]; then
			while IFS= read -r line; do
				echo "[DEBUG] passwd stderr ($account_name): $line"
			done < "$stderr_log"
		fi
		rm -f "$stderr_log"
	echo "[DEBUG] passwd -d exit code for $account_name: $status"
	if [[ $status -ne 0 ]]; then
		echo "[FAIL] passwd -d failed for account: $account_name"
		return "$status"
	fi
	echo "[DEBUG] Password entry cleared for account: $account_name"
	return 0
}


	log_chroot_step "Ensuring password packages are installed"
	if ! install_packages_if_missing shadow pambase; then
		echo "[FAIL] Could not install required password packages: shadow pambase"
		exit 1
	fi
fi

	if command -v getent >/dev/null 2>&1; then
		id shadow >/dev/null 2>&1 || true
		if ! getent group shadow >/dev/null 2>&1; then
			echo "[WARN] group 'shadow' does not exist; creating it"
			if ! groupadd -r shadow; then
				echo "[FAIL] Could not create required group: shadow"
				exit 1
			fi
		fi
	fi
echo "[DEBUG] Validating /etc/shadow before password operations"
if [[ ! -f /etc/shadow ]]; then
	echo "[FAIL] /etc/shadow is missing inside the target chroot"
	exit 1
	echo "[DEBUG] id shadow output:"
	id shadow 2>&1 || true
	echo "[DEBUG] ls -l /etc/shadow output before normalization:"
	ls -l /etc/shadow 2>&1 || true
fi
if ! chown root:shadow /etc/shadow; then
	echo "[FAIL] Could not set owner root:shadow on /etc/shadow"
	exit 1
fi
if ! chmod 640 /etc/shadow; then
	echo "[FAIL] Could not set mode 640 on /etc/shadow"
	exit 1
fi
echo "[DEBUG] /etc/shadow permissions normalized"

if ! id -u root >/dev/null 2>&1; then
	echo "[FAIL] root account is missing inside the target chroot"
	exit 1
fi

echo "[DEBUG] ls -l /etc/shadow output after normalization:"
ls -l /etc/shadow 2>&1 || true

echo "[DEBUG] Password execution order: root password -> user creation -> user password"
set_account_password root "$TARGET_ROOT_PASSWORD" || exit 1

if ! id -u "$TARGET_USERNAME" >/dev/null 2>&1; then
	echo "[DEBUG] Creating user account: $TARGET_USERNAME"
	if ! useradd -m -G wheel -s /bin/bash "$TARGET_USERNAME"; then
		echo "[FAIL] useradd failed for '$TARGET_USERNAME'"
		exit 1
	fi
fi
if ! id -u "$TARGET_USERNAME" >/dev/null 2>&1; then
	echo "[FAIL] useradd did not create user '$TARGET_USERNAME'"
	exit 1
fi
set_account_password "$TARGET_USERNAME" "$TARGET_USER_PASSWORD" || exit 1

log_chroot_step "Configuring sudo permissions"
if grep -q '^# %wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
	sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
elif ! grep -q '^%wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
	echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
fi
EOF
}
