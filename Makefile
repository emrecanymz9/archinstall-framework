.PHONY: deps full-deps mirror run dev log clean

deps:
	pacman -Sy archlinux-keyring --noconfirm
	pacman -S --needed --noconfirm git dialog reflector

full-deps:
	pacman -Sy archlinux-keyring --noconfirm
	pacman -S --needed --noconfirm base-devel git dialog reflector parted dosfstools e2fsprogs btrfs-progs arch-install-scripts

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