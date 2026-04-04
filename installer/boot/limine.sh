#!/usr/bin/env bash

limine_chroot_snippet() {
	local boot_mode=${1:-bios}

	cat <<'EOF'
log_chroot_step "Installing Limine"
install_packages_if_missing limine || true
mkdir -p /boot

MICROCODE_MODULE_LINE=""
if [[ -f /boot/intel-ucode.img ]]; then
	MICROCODE_MODULE_LINE="    MODULE_PATH=boot():/intel-ucode.img"
elif [[ -f /boot/amd-ucode.img ]]; then
	MICROCODE_MODULE_LINE="    MODULE_PATH=boot():/amd-ucode.img"
fi

cat > /boot/limine.cfg <<EOT
TIMEOUT=3

:Arch Linux
    PROTOCOL=linux
    KERNEL_PATH=boot():/vmlinuz-linux
$(if [[ -n "$MICROCODE_MODULE_LINE" ]]; then printf '%s\n' "$MICROCODE_MODULE_LINE"; fi)
    MODULE_PATH=boot():/initramfs-linux.img
    CMDLINE=$(build_kernel_cmdline)
EOT

if [[ $BOOT_MODE == "uefi" ]]; then
	install -d -m 0755 /boot/EFI/BOOT
	if [[ -f /usr/share/limine/BOOTX64.EFI ]]; then
		install -m 0644 /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
	fi
	if [[ -f /usr/share/limine/BOOTIA32.EFI ]]; then
		install -m 0644 /usr/share/limine/BOOTIA32.EFI /boot/EFI/BOOT/BOOTIA32.EFI
	fi
else
	if [[ -f /usr/share/limine/limine-bios.sys ]]; then
		install -m 0644 /usr/share/limine/limine-bios.sys /boot/limine-bios.sys
	fi
	limine bios-install "$TARGET_DISK"
fi

echo "[DEBUG] /boot/limine.cfg"
cat /boot/limine.cfg
EOF
}
