.PHONY: deps mirror clone run run-dialog dev

deps:
	pacman -Sy archlinux-keyring --noconfirm
	pacman -S --needed --noconfirm dialog git reflector parted dosfstools e2fsprogs btrfs-progs

mirror:
	reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

clone:
	cd .. && rm -rf archinstall-framework && git clone https://github.com/emrecanymz9/archinstall-framework.git

run:
	bash installer/install.sh

run-dialog:
	INSTALL_UI_MODE=dialog bash installer/install.sh

dev:
	SKIP_PARTITION=true SKIP_PACSTRAP=true bash installer/install.sh