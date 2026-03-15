#!/usr/bin/env bash
# installer/ui.sh – dialog UI helpers with adaptive terminal sizing
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Safe TERM default – dialog requires a valid terminal type.
# If TERM is unset (e.g. running under a systemd service or bare TTY that
# never exported TERM), dialog outputs raw escape sequences as literal text.
# ---------------------------------------------------------------------------
: "${TERM:=linux}"
export TERM

# ---------------------------------------------------------------------------
# strip_ansi – remove ANSI / VT escape sequences from a string.
# dialog does not interpret ANSI codes; passing coloured output from commands
# (e.g. sbctl, lsblk --color) directly to --msgbox/--menu causes visible
# garbage like \E[0m or ^[[32m in the dialog box.
#
# Strips:
#   CSI sequences  ESC [ <params> <letter>   (colours, cursor movement, etc.)
#   OSC sequences  ESC ] <text> BEL          (window titles, hyperlinks)
#   2/3-char ESC   ESC [ () # % * + ] <opt-intermediate> <final>
#   Remaining bare ESC + one character
# ---------------------------------------------------------------------------
strip_ansi() {
    # Requires GNU sed (standard on Arch Linux / any systemd-based distro).
    printf '%s' "$*" \
        | sed 's/\x1B\[[0-9;:]*[A-Za-z]//g
               s/\x1B][^\x07]*\x07//g
               s/\x1B[][()#%*+][0-9A-Za-z]//g
               s/\x1B.//g'
}

# ---------------------------------------------------------------------------
# Adaptive dimensions (recalculated on each call so resizing works)
# ---------------------------------------------------------------------------
_dlg_dims() {
    local h w mh
    h=$(tput lines  2>/dev/null || echo 24)
    w=$(tput cols   2>/dev/null || echo 80)
    # Subtract 4 from each dimension to leave room for dialog borders/shadow
    h=$(( h - 4 < 10 ? 10 : h - 4 ))   # minimum height: 10 lines
    w=$(( w - 4 < 54 ? 54 : w - 4 ))   # minimum width:  54 cols (readable menus)
    mh=$(( h - 8 <  3 ?  3 : h - 8 ))  # menu list height: dialog h minus title/buttons
    echo "$h $w $mh"
}

# Internal: run dialog, write result to stdout, return dialog's exit code
# Usage: _dlg <dialog args…>
_dlg() {
    local tmpfile rc
    tmpfile=$(mktemp)
    dialog --backtitle "$(strip_ansi "${UI_BACKTITLE:-ArchInstall Framework}")" "$@" 2>"$tmpfile"; rc=$?
    cat "$tmpfile"; rm -f "$tmpfile"
    return "$rc"
}

# ---------------------------------------------------------------------------
# Public helpers
# All text/title/prompt arguments are passed through strip_ansi() so that
# any ANSI colour codes captured from system commands (lsblk, sbctl, etc.)
# are never rendered as literal escape sequences inside a dialog box.
# ---------------------------------------------------------------------------

# ui_msgbox <title> <text>
ui_msgbox() {
    read -r H W _ <<< "$(_dlg_dims)"
    dialog --backtitle "$(strip_ansi "${UI_BACKTITLE:-ArchInstall Framework}")" \
           --title "$(strip_ansi "$1")" --msgbox "$(strip_ansi "$2")" "$H" "$W"
}

# ui_yesno <title> <text>  →  returns 0 for Yes, 1 for No
ui_yesno() {
    read -r H W _ <<< "$(_dlg_dims)"
    dialog --backtitle "$(strip_ansi "${UI_BACKTITLE:-ArchInstall Framework}")" \
           --title "$(strip_ansi "$1")" --yesno "$(strip_ansi "$2")" "$H" "$W"
}

# ui_menu <title> <prompt> <tag1> <item1> [tag2 item2 …]  →  stdout: chosen tag
ui_menu() {
    local title="$1" prompt="$2"; shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$(strip_ansi "$title")" --menu "$(strip_ansi "$prompt")" "$H" "$W" "$MH" "$@"
}

# ui_radiolist <title> <prompt> <tag1> <item1> <on|off> …  →  stdout: chosen tag
ui_radiolist() {
    local title="$1" prompt="$2"; shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$(strip_ansi "$title")" --radiolist "$(strip_ansi "$prompt")" "$H" "$W" "$MH" "$@"
}

# ui_checklist <title> <prompt> <tag1> <item1> <on|off> …  →  stdout: space-sep tags
ui_checklist() {
    local title="$1" prompt="$2"; shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$(strip_ansi "$title")" --checklist "$(strip_ansi "$prompt")" "$H" "$W" "$MH" "$@"
}

# ui_inputbox <title> <prompt> [default]  →  stdout: entered text
ui_inputbox() {
    local title="$1" prompt="$2" default="${3:-}"
    read -r H W _ <<< "$(_dlg_dims)"
    _dlg --title "$(strip_ansi "$title")" --inputbox "$(strip_ansi "$prompt")" "$H" "$W" "$default"
}

# ui_passwordbox <title> <prompt>  →  stdout: entered password
ui_passwordbox() {
    local title="$1" prompt="$2"
    read -r H W _ <<< "$(_dlg_dims)"
    _dlg --title "$(strip_ansi "$title")" --insecure --passwordbox "$(strip_ansi "$prompt")" "$H" "$W"
}

# ui_gauge <title> <text> <pct>  (non-interactive progress; use with a loop)
ui_gauge_msg() {
    local title="$1" text="$2" pct="$3"
    read -r H W _ <<< "$(_dlg_dims)"
    echo "$pct" | dialog --backtitle "$(strip_ansi "${UI_BACKTITLE:-ArchInstall Framework}")" \
        --title "$(strip_ansi "$title")" --gauge "$(strip_ansi "$text")" 7 "$W" "$pct"
}

# ---------------------------------------------------------------------------
# Dependency check – call before starting the installer
# ---------------------------------------------------------------------------
require_tools() {
    local missing=()
    for cmd in dialog jq parted lsblk blkid cryptsetup pacstrap genfstab \
               arch-chroot mkfs.fat mkfs.btrfs mkfs.ext4 efibootmgr; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: Missing required tools: ${missing[*]}"
        echo "Install with: pacman -Sy --needed dialog jq parted cryptsetup dosfstools btrfs-progs e2fsprogs efibootmgr arch-install-scripts"
        exit 1
    fi

    # Validate that TERM is usable by dialog (tput smoke-test).
    # An unset or unknown TERM causes dialog to emit raw escape sequences.
    if ! tput clear &>/dev/null; then
        export TERM=linux
    fi
}
