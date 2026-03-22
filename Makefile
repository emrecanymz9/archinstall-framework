.PHONY: deps mirror run dev log clean

deps:
	@if ! command -v make >/dev/null 2>&1; then \
		echo "make was not found; installing base-devel"; \
		pacman -S --needed --noconfirm base-devel; \
	fi
	pacman -Sy archlinux-keyring --noconfirm
	pacman -S --needed --noconfirm base-devel dialog git reflector parted dosfstools e2fsprogs btrfs-progs arch-install-scripts

mirror:
	reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

run:
	bash installer/install.sh

dev:
	DEV_MODE=1 bash installer/install.sh

log:
	less /tmp/archinstall_install.log

clean:
	umount -R /mnt || true