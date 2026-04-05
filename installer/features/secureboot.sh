#!/usr/bin/env bash

secure_boot_mode_label() {
	case ${1:-disabled} in
		disabled)
			printf 'Disabled\n'
			;;
		setup)
			printf 'Setup Foundation\n'
			;;
		*)
			printf '%s\n' "$1"
			;;
	esac
}

select_secure_boot_mode() {
	local current_mode=${1:-disabled}
	local boot_mode=${2:-bios}
	local secure_boot_state=${3:-unsupported}

	if [[ $boot_mode != "uefi" ]]; then
		printf 'disabled\n'
		return 0
	fi

	menu "Secure Boot" "Choose the Secure Boot strategy.\n\nCurrent firmware state: $(secure_boot_state_label "$secure_boot_state")\n\nExample: choose Setup Foundation when you want a UKI-ready, best-effort Secure Boot flow.\nConstraint: the final behavior depends on the selected bootloader." 18 78 4 \
		"disabled" "Do not configure Secure Boot" \
		"setup" "Prepare a non-fatal sbctl-based Secure Boot foundation"

	case $DIALOG_STATUS in
		0)
			printf '%s\n' "$DIALOG_RESULT"
			return 0
			;;
		*)
			return 1
			;;
	esac
}

secure_boot_packages() {
	local secure_boot_mode=${1:-disabled}
	local boot_mode=${2:-bios}
	local bootloader=${3:-$(default_bootloader_for_mode "$boot_mode")}
	local -n package_ref=${4:?package reference is required}

	package_ref=()
	if [[ $boot_mode != "uefi" ]]; then
		return 0
	fi

	case $secure_boot_mode in
		setup)
			package_ref+=(sbctl)
			if [[ $bootloader == "systemd-boot" ]]; then
				package_ref+=(systemd-ukify)
			fi
			;;
		*)
			;;
	esac
}

secure_boot_guidance_text() {
	local secure_boot_mode=${1:-disabled}
	local boot_mode=${2:-bios}
	local secure_boot_state=${3:-unsupported}

	if [[ $boot_mode != "uefi" ]]; then
		printf 'Secure Boot is not available in BIOS mode.'
		return 0
	fi

	case $secure_boot_mode in
		disabled)
			printf 'Secure Boot configuration is disabled.'
			;;
		setup)
			printf 'Setup foundation mode installs Secure Boot tooling and keeps the workflow non-fatal. systemd-boot receives the full UKI path. GRUB and Limine remain advanced/manual Secure Boot configurations.'
			;;
		*)
			printf 'Secure Boot mode: %s' "$secure_boot_mode"
			;;
	esac

	if [[ $secure_boot_state == "enabled" ]]; then
		printf '\n\nFirmware reports Secure Boot enabled. The installer will not fail hard, but you should verify your boot chain before enabling the new system for unattended use.'
	fi
}

secure_boot_chroot_snippet() {
	cat <<'EOF'
write_secure_boot_notice() {
	install -d -m 0700 /root
	cat > /root/ARCHINSTALL_SECURE_BOOT.txt <<EOT
Secure Boot firmware state: $TARGET_CURRENT_SECURE_BOOT_STATE
Secure Boot mode: $TARGET_SECURE_BOOT_MODE
Firmware setup mode: $TARGET_SECURE_BOOT_SETUP_MODE
Install profile: $TARGET_INSTALL_PROFILE
Environment: $TARGET_ENVIRONMENT_VENDOR
GPU: $TARGET_GPU_VENDOR

This installer uses mkinitcpio + ukify to build a Unified Kernel Image when Secure Boot setup is enabled.
It keeps the workflow non-fatal: VM firmware quirks, missing tooling, or signing failures will not abort the install.

If the GPU is NVIDIA, the installer enables early driver modules and appends nvidia_drm.modeset=1 to the kernel command line.
If the environment is virtualized, automatic key enrollment is skipped unless you handle firmware ownership manually.

Recommended follow-up commands:
  sbctl status
  sbctl create-keys
  sbctl enroll-keys -m
  sbctl verify
EOT
}

configure_nvidia_mkinitcpio() {
	if [[ $TARGET_GPU_VENDOR != "nvidia" ]]; then
		return 0
	fi

	if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
		sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
	else
		echo 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' >> /etc/mkinitcpio.conf
	fi
}

write_uki_configuration() {
	local kernel_cmdline=""

	install -d -m 0755 /etc/kernel /boot/EFI/Linux
	kernel_cmdline="$(build_kernel_cmdline)"
	printf '%s\n' "$kernel_cmdline" > /etc/kernel/cmdline
	cat > /etc/mkinitcpio.d/linux.preset <<'EOT'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux.efi"
fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
EOT
}

sign_efi_binary_if_present() {
	local binary_path=
	binary_path=${1:-}
	[[ -n $binary_path ]] || return 0
	[[ -e $binary_path ]] || return 0

	if ! sbctl sign -s "$binary_path"; then
		echo "[WARN] sbctl could not sign $binary_path"
		return 1
	fi
	return 0
}

configure_secure_boot_mode() {
	if [[ $BOOT_MODE != "uefi" ]]; then
		return 0
	fi

	case $TARGET_SECURE_BOOT_MODE in
		disabled)
			return 0
			;;
		setup)
			log_chroot_step "Preparing Secure Boot and UKI tooling"
			if ! command -v sbctl >/dev/null 2>&1; then
				echo "[WARN] sbctl is not installed in the target system."
				mkinitcpio -P || true
				write_secure_boot_notice
				return 0
			fi
			if ! command -v ukify >/dev/null 2>&1; then
				echo "[WARN] ukify is not installed in the target system. Falling back to the standard initramfs path."
				mkinitcpio -P || true
				write_secure_boot_notice
				return 0
			fi
			configure_nvidia_mkinitcpio
			write_uki_configuration
			sbctl status || true
			if [[ ! -d /var/lib/sbctl/keys ]]; then
				sbctl create-keys || true
			fi
			if [[ $TARGET_SECURE_BOOT_SETUP_MODE == "setup" && $TARGET_ENVIRONMENT_VENDOR == "baremetal" ]]; then
				sbctl enroll-keys -m || true
			elif [[ $TARGET_ENVIRONMENT_VENDOR != "baremetal" ]]; then
				echo "[WARN] Virtualized environment detected. Skipping automatic key enrollment."
			fi
			mkinitcpio -P || {
				echo "[WARN] mkinitcpio failed to build UKIs. Continuing with the rest of the install."
				write_secure_boot_notice
				return 0
			}
			sign_efi_binary_if_present /boot/EFI/Linux/arch-linux.efi || true
			sign_efi_binary_if_present /boot/EFI/Linux/arch-linux-fallback.efi || true
			sign_efi_binary_if_present /boot/EFI/systemd/systemd-bootx64.efi || true
			sign_efi_binary_if_present /boot/EFI/BOOT/BOOTX64.EFI || true
			write_secure_boot_notice
			;;
		*)
			;;
	esac
}

configure_secure_boot_mode
EOF
}
