#!/usr/bin/env bash
# installer/ui.sh - dialog UI helpers with adaptive terminal sizing
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Safe TERM default - dialog requires a valid terminal type.
# If TERM is unset or "dumb" (e.g. running under a systemd service, bare TTY,
# or piped session), dialog outputs raw escape sequences as literal text.
# Use linux for a physical/virtual console, xterm-256color for everything else.
# ---------------------------------------------------------------------------
if [[ -z "${TERM:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    if [[ -t 0 ]]; then
        export TERM=linux           # physical/virtual console (TTY)
    else
        export TERM=xterm-256color  # SSH or other terminal emulator
    fi
fi

# ---------------------------------------------------------------------------
# Set locale to C.UTF-8 so that dialog draws box characters correctly and
# locale-dependent collation/encoding issues do not affect the installer UI.
# ---------------------------------------------------------------------------
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ---------------------------------------------------------------------------
# Disable colored output from subprocesses (pacman, lsblk, etc.) so that ANSI
# escape codes cannot leak into text displayed inside dialog windows.
# Override with NO_COLOR=0 in your environment if you need colours elsewhere.
# ---------------------------------------------------------------------------
export NO_COLOR=1

# ---------------------------------------------------------------------------
# strip_ansi - remove ANSI / VT escape sequences and unsafe characters from a
# string so that it is safe to pass as dialog box text.
#
# Strips:
#   - Real ESC (0x1B) byte CSI sequences including DEC private sequences
#     (\033[...h/l, \033[?...h/l, mouse control, etc.)
#   - OSC / DCS sequences (\033] and \033P)
#   - Other VT sequences (\033 followed by any character)
#   - Literal backslash-escaped sequences (\033[, \e[, \x1b[)
#   - Carriage return (\r) which causes dialog rendering issues
#   - Non-printable control characters (0x00-0x08, 0x0B-0x0C, 0x0E-0x1F, 0x7F)
#   - Non-ASCII bytes (>0x7F) which display as garbage on many Linux TTYs
#
# Preserves: printable ASCII (0x20-0x7E), TAB (0x09), and LF (0x0A).
# ---------------------------------------------------------------------------
strip_ansi() {
    printf '%s' "$*" | LC_ALL=C sed \
        -e 's/\x1B\[[0-9;:?<>!]*[A-Za-z]//g' \
        -e 's/\x1B][^\x07]*\x07//g' \
        -e 's/\x1BP[^\\]*\\//g' \
        -e 's/\x1B[][()#%*+][0-9A-Za-z]//g' \
        -e 's/\x1B.//g' \
        -e 's/\\033\[[0-9;:?<>!]*[A-Za-z]//g' \
        -e 's/\\e\[[0-9;:?<>!]*[A-Za-z]//g' \
        -e 's/\\x1b\[[0-9;:?<>!]*[A-Za-z]//g' \
        -e 's/\r//g' | \
    tr -cd '\11\12\40-\176'
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
# Usage: _dlg <dialog args...>
_dlg() {
    local tmpfile rc
    tmpfile=$(mktemp)
    # Reset terminal to a sane state before launching dialog.
    # On VM/TTY consoles (e.g. VMware) text written to the terminal before the
    # first dialog call can leave the TTY in a state where ncurses waits for a
    # keypress.  stty sane resets line-discipline flags and clear wipes any
    # text written to the TTY, so dialog appears immediately without requiring
    # the user to press Enter.
    stty sane 2>/dev/null || true
    clear 2>/dev/null || true
    dialog --backtitle "$(strip_ansi "${UI_BACKTITLE:-ArchInstall Framework}")" "$@" 2>"$tmpfile"; rc=$?
    # Strip stray escape sequences that some dialog/ncurses versions write to
    # stderr alongside the selection result; these would otherwise appear as
    # garbage in the next dialog's prompt text.
    LC_ALL=C sed \
        -e 's/\x1B\[[0-9;:?<>!]*[A-Za-z]//g' \
        -e 's/\x1B.//g' \
        -e 's/\r//g' < "$tmpfile" | tr -cd '\11\12\40-\176'
    rm -f "$tmpfile"
    return "$rc"
}

# ---------------------------------------------------------------------------
# Public helpers
# All text/title/prompt arguments are passed through strip_ansi() so that
# any ANSI colour codes captured from system commands are never rendered as
# literal escape sequences inside a dialog box.
# ---------------------------------------------------------------------------

# ui_msgbox <title> <text>
ui_msgbox() {
    read -r H W _ <<< "$(_dlg_dims)"
    _dlg --title "$(strip_ansi "$1")" --msgbox "$(strip_ansi "$2")" "$H" "$W"
}

# ui_yesno <title> <text>  ->  returns 0 for Yes, 1 for No
ui_yesno() {
    read -r H W _ <<< "$(_dlg_dims)"
    _dlg --title "$(strip_ansi "$1")" --yesno "$(strip_ansi "$2")" "$H" "$W"
}

# ui_menu <title> <prompt> <tag1> <item1> [tag2 item2 ...]  ->  stdout: chosen tag
ui_menu() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$title" --menu "$prompt" "$H" "$W" "$MH" "$@"
}

# ui_radiolist <title> <prompt> <tag1> <item1> <on|off> ...  ->  stdout: chosen tag
ui_radiolist() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$title" --radiolist "$prompt" "$H" "$W" "$MH" "$@"
}

# ui_checklist <title> <prompt> <tag1> <item1> <on|off> ...  ->  stdout: space-sep tags
ui_checklist() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$title" --checklist "$prompt" "$H" "$W" "$MH" "$@"
}

# ui_inputbox <title> <prompt> [default]  ->  stdout: entered text
ui_inputbox() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    local default="${3:-}"
    read -r H W _ <<< "$(_dlg_dims)"
    _dlg --title "$title" --inputbox "$prompt" "$H" "$W" "$default"
}

# ui_passwordbox <title> <prompt>  ->  stdout: entered password
ui_passwordbox() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    read -r H W _ <<< "$(_dlg_dims)"
    _dlg --title "$title" --insecure --passwordbox "$prompt" "$H" "$W"
}

# ui_gauge <title> <text> <pct>  (non-interactive progress; use with a loop)
ui_gauge_msg() {
    local title; title=$(strip_ansi "$1")
    local text;  text=$(strip_ansi "$2")
    local pct="$3"
    read -r H W _ <<< "$(_dlg_dims)"
    echo "$pct" | dialog --backtitle "$(strip_ansi "${UI_BACKTITLE:-ArchInstall Framework}")" \
        --title "$title" --gauge "$text" 7 "$W" "$pct"
}

# ---------------------------------------------------------------------------
# Dependency check - call before starting the installer
# ---------------------------------------------------------------------------
require_tools() {
    # Check for dialog first: without it we cannot show any TUI at all.
    if ! command -v dialog &>/dev/null; then
        echo "ERROR: 'dialog' is not installed." >&2
        echo "       The installer requires dialog to draw its TUI." >&2
        echo "       Install it with:" >&2
        echo "         pacman -Sy --needed dialog" >&2
        exit 1
    fi

    local missing=()
    for cmd in jq parted lsblk blkid cryptsetup pacstrap genfstab \
               arch-chroot mkfs.fat mkfs.btrfs mkfs.ext4 efibootmgr; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: Missing required tools: ${missing[*]}" >&2
        echo "       Install with:" >&2
        echo "         pacman -Sy --needed dialog jq parted cryptsetup dosfstools btrfs-progs e2fsprogs efibootmgr arch-install-scripts" >&2
        exit 1
    fi

    # Validate that TERM is usable by dialog (tput smoke-test).
    # An unknown TERM value causes dialog to emit raw escape sequences even
    # when the variable is set.  Apply the same TTY detection as at startup.
    if ! tput clear &>/dev/null; then
        if [[ -t 0 ]]; then
            export TERM=linux
        else
            export TERM=xterm-256color
        fi
    fi
}
