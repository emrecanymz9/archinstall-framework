collect_boot_mode(){ [ -d /sys/firmware/efi ] && STATE_BOOTMODE=UEFI || STATE_BOOTMODE=BIOS; }
