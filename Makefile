.PHONY: deps full-deps mirror run dev log clean install clone

REPO_URL ?= https://github.com/emrecanymz9/archinstall-framework.git
REPO_DIR ?= archinstall-framework

deps:
	pacman -Sy archlinux-keyring --noconfirm
	pacman -Sy --noconfirm make git dialog reflector

full-deps:
	pacman -Sy archlinux-keyring --noconfirm
	pacman -Sy --noconfirm make base-devel git dialog reflector parted dosfstools e2fsprogs btrfs-progs arch-install-scripts

install:
	bash installer/install.sh

clone:
	git clone $(REPO_URL)
	cd $(REPO_DIR) && bash installer/install.sh

mirror:
	reflector --latest 10 --protocol https --connection-timeout 5 --sort rate --save /etc/pacman.d/mirrorlist

run:
	bash installer/install.sh

dev:
	DEV_MODE=1 bash installer/install.sh

log:
	less /tmp/archinstall_install.log

clean:
	@if [ -f "$(CURDIR)/scripts/cleanup.sh" ]; then \
		bash "$(CURDIR)/scripts/cleanup.sh"; \
	else \
		echo "cleanup script not found"; \
	fi