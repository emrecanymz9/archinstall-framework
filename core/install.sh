#!/usr/bin/env bash

source core/ui.sh
source core/state.sh
source core/bootmode.sh

require_tools
init_state

bootmode_screen

dialog --msgbox "Boot mode locked to UEFI.\n\nProceeding..." 10 50

dialog --msgbox "Installer skeleton working." 8 40

clear
