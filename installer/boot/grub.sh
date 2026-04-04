#!/usr/bin/env bash

grub_chroot_snippet() {
	local boot_mode=${1:-bios}

	if [[ $boot_mode == "uefi" ]]; then
		cat <<'EOF'
log_chroot_step "Installing GRUB"
grub_cmdline="$(build_kernel_cmdline)"
if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
	sed -i "s#^GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX=\"$grub_cmdline\"#" /etc/default/grub
else
	printf '%s\n' "GRUB_CMDLINE_LINUX=\"$grub_cmdline\"" >> /etc/default/grub
fi
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux
grub-mkconfig -o /boot/grub/grub.cfg

echo "[DEBUG] /etc/default/grub"
cat /etc/default/grub
echo "[DEBUG] Generated grub.cfg linux lines"
grep -n 'linux.*/vmlinuz-linux' /boot/grub/grub.cfg || true
EOF
		return 0
	fi

	cat <<'EOF'
log_chroot_step "Installing GRUB"

if [[ $BOOT_MODE == "bios" ]]; then
	GRUB_DISK_LABEL="$(parted -s "$TARGET_DISK" print 2>/dev/null | awk '/Partition Table:/ {print $3}' || true)"
	if [[ "$GRUB_DISK_LABEL" == "gpt" ]]; then
		if ! parted -s "$TARGET_DISK" print 2>/dev/null | grep -qi 'bios_grub'; then
			echo "[FAIL] BIOS install on GPT disk requires a bios_grub partition. None found on $TARGET_DISK."
			echo "[FAIL] Create a 1 MiB unformatted partition with the bios_grub flag and retry."
			exit 1
		fi
		echo "[INFO] bios_grub partition confirmed on GPT disk - proceeding with GRUB embed."
	fi
fi

grub_cmdline="$(build_kernel_cmdline)"
if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
	sed -i "s#^GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX=\"$grub_cmdline\"#" /etc/default/grub
else
	printf '%s\n' "GRUB_CMDLINE_LINUX=\"$grub_cmdline\"" >> /etc/default/grub
fi
if grep -q '^GRUB_DISABLE_LINUX_UUID=' /etc/default/grub; then
	sed -i 's/^GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
else
	echo 'GRUB_DISABLE_LINUX_UUID=true' >> /etc/default/grub
fi

grub-install --target=i386-pc "$TARGET_DISK"
grub-mkconfig -o /boot/grub/grub.cfg

echo "[DEBUG] /etc/default/grub"
cat /etc/default/grub
echo "[DEBUG] Generated grub.cfg linux lines"
grep -n 'linux.*/vmlinuz-linux' /boot/grub/grub.cfg || true
EOF
}
