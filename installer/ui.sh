#!/usr/bin/env bash
# installer/ui.sh – dialog UI helpers with adaptive terminal sizing
set -Eeuo pipefail

# ── TERM fallback ───────────────────────────────────────────────────────────
# dialog and tput both need a valid terminal type.  On some consoles (e.g.
# early boot, SSH without TERM set, or piped sessions) TERM may be unset or
# set to "dumb", which causes dialog to output literal escape sequences
# instead of drawing its TUI correctly.  Pick a safe default automatically.
if [[ -z "${TERM:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    if [[ -t 0 ]]; then
        export TERM=linux           # physical/virtual console (TTY)
    else
        export TERM=xterm-256color  # SSH or other terminal emulator
    fi
fi

# ── Disable colored output from subprocesses ───────────────────────────────
# Prevents tools like lsblk, pacman, etc. from injecting ANSI escape codes
# into text that ends up displayed inside dialog windows.
# Override with NO_COLOR=0 in your environment if you need colours elsewhere.
export NO_COLOR=1

# ---------------------------------------------------------------------------
# _strip_ansi <text>  →  stdout: text with ANSI/escape sequences removed
#
# Removes both real ESC sequences (ESC [ … m) and the literal backslash-
# encoded variants some tools emit (\\e[, \\033[, \\x1b[, \\[…m).
# ---------------------------------------------------------------------------
_strip_ansi() {
    local text="${1:-}"
    [[ -z "$text" ]] && return 0
    printf '%s' "$text" \
        | sed \
            -e 's/\x1b\[[0-9;]*[mKHfABCDJsuhlM]//g' \
            -e 's/\\e\[[0-9;]*[mKHfABCDJsuhlM]//g'   \
            -e 's/\\033\[[0-9;]*[mKHfABCDJsuhlM]//g'  \
            -e 's/\\x1b\[[0-9;]*[mKHfABCDJsuhlM]//g'  \
            -e 's/\\\[[0-9;]*[mKHfABCDJsuhlM]//g'
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
    dialog --backtitle "${UI_BACKTITLE:-ArchInstall Framework}" "$@" 2>"$tmpfile"; rc=$?
    cat "$tmpfile"; rm -f "$tmpfile"
    return "$rc"
}

# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

# ui_msgbox <title> <text>
ui_msgbox() {
    local text; text=$(_strip_ansi "${2:-}")
    read -r H W _ <<< "$(_dlg_dims)"
    dialog --backtitle "${UI_BACKTITLE:-ArchInstall Framework}" \
           --title "$1" --msgbox "$text" "$H" "$W"
}

# ui_yesno <title> <text>  →  returns 0 for Yes, 1 for No
ui_yesno() {
    local text; text=$(_strip_ansi "${2:-}")
    read -r H W _ <<< "$(_dlg_dims)"
    dialog --backtitle "${UI_BACKTITLE:-ArchInstall Framework}" \
           --title "$1" --yesno "$text" "$H" "$W"
}

# ui_menu <title> <prompt> <tag1> <item1> [tag2 item2 …]  →  stdout: chosen tag
ui_menu() {
    local title="$1" prompt; prompt=$(_strip_ansi "${2:-}"); shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$title" --menu "$prompt" "$H" "$W" "$MH" "$@"
}

# ui_radiolist <title> <prompt> <tag1> <item1> <on|off> …  →  stdout: chosen tag
ui_radiolist() {
    local title="$1" prompt; prompt=$(_strip_ansi "${2:-}"); shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$title" --radiolist "$prompt" "$H" "$W" "$MH" "$@"
}

# ui_checklist <title> <prompt> <tag1> <item1> <on|off> …  →  stdout: space-sep tags
ui_checklist() {
    local title="$1" prompt; prompt=$(_strip_ansi "${2:-}"); shift 2
    read -r H W MH <<< "$(_dlg_dims)"
    _dlg --title "$title" --checklist "$prompt" "$H" "$W" "$MH" "$@"
}

# ui_inputbox <title> <prompt> [default]  →  stdout: entered text
ui_inputbox() {
    local title="$1"
    local default="${3:-}"
    local prompt; prompt=$(_strip_ansi "${2:-}")
    read -r H W _ <<< "$(_dlg_dims)"
    _dlg --title "$title" --inputbox "$prompt" "$H" "$W" "$default"
}

# ui_passwordbox <title> <prompt>  →  stdout: entered password
ui_passwordbox() {
    local title="$1" prompt; prompt=$(_strip_ansi "${2:-}")
    read -r H W _ <<< "$(_dlg_dims)"
    _dlg --title "$title" --insecure --passwordbox "$prompt" "$H" "$W"
}

# ui_gauge <title> <text> <pct>  (non-interactive progress; use with a loop)
ui_gauge_msg() {
    local title="$1"
    local pct="$3"
    local text; text=$(_strip_ansi "${2:-}")
    read -r H W _ <<< "$(_dlg_dims)"
    echo "$pct" | dialog --backtitle "${UI_BACKTITLE:-ArchInstall Framework}" \
        --title "$title" --gauge "$text" 7 "$W" "$pct"
}

# ---------------------------------------------------------------------------
# Dependency check – call before starting the installer
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
}
