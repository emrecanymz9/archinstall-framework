#!/usr/bin/env bash
# installer/ui.sh - dialog UI helpers with adaptive terminal sizing
#
# UI_MODE is set automatically:
#   dialog  - full TUI dialog (default when dialog is installed)
#   bash    - plain bash fallback (select/read/echo) used during debug/dev
#             or when the 'dialog' package is not available.
#
# You can force a mode before sourcing this file:
#   export UI_MODE=bash    # always use bash fallback
#   export UI_MODE=dialog  # require dialog (exit if missing)
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
# UI_MODE auto-detection
#   If the caller already exported UI_MODE, respect it.
#   Otherwise: use "dialog" when dialog is installed, "bash" otherwise.
# ---------------------------------------------------------------------------
if [[ -z "${UI_MODE:-}" ]]; then
    if command -v dialog &>/dev/null; then
        UI_MODE=dialog
    else
        UI_MODE=bash
    fi
fi
export UI_MODE

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
    # keypress.  stty sane resets line-discipline flags.
    # clear is redirected to /dev/tty so it goes to the actual terminal and is
    # NOT captured when _dlg is called via $() command substitution.  Without
    # this redirection, clear's escape sequences (\033[H\033[2J) pollute the
    # captured stdout, contaminating choice variables with garbage like "[H[2J".
    stty sane 2>/dev/null || true
    clear >/dev/tty 2>/dev/null || true
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

# ===========================================================================
# BASH FALLBACK HELPERS
# Used when UI_MODE=bash (dialog not installed, or forced for debugging).
# These use plain bash built-ins: echo, read, select.
# No extra packages needed — works on any Linux tty/console out of the box.
# ===========================================================================

_bash_separator() {
    echo "========================================"
}

# _bash_msgbox <title> <text>
_bash_msgbox() {
    local title="$1" text="$2"
    _bash_separator
    echo "  $title"
    _bash_separator
    echo "$text"
    echo ""
    read -rp "  [Press Enter to continue]" _dummy </dev/tty || true
    echo ""
}

# _bash_yesno <title> <text>  ->  returns 0 for yes, 1 for no
_bash_yesno() {
    local title="$1" text="$2" ans
    _bash_separator
    echo "  $title"
    _bash_separator
    echo "$text"
    echo ""
    while true; do
        read -rp "  Proceed? [y/n]: " ans </dev/tty || { echo ""; return 1; }
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) echo "  Please enter y or n." ;;
        esac
    done
}

# _bash_menu <title> <prompt> <tag1> <item1> [tag2 item2 ...]  ->  stdout: chosen tag
# Tags and items are interleaved: tag1 item1 tag2 item2 ...
_bash_menu() {
    local title="$1" prompt="$2"
    shift 2
    local -a tags items
    while [[ $# -ge 2 ]]; do
        tags+=("$1"); items+=("$2"); shift 2
    done

    _bash_separator >&2
    echo "  $title" >&2
    _bash_separator >&2
    echo "  $prompt" >&2
    echo "" >&2

    local i
    for (( i=0; i<${#tags[@]}; i++ )); do
        printf "  %2d) %s\n" $(( i+1 )) "${items[$i]}" >&2
    done
    echo "" >&2

    local choice
    while true; do
        read -rp "  Enter number [1-${#tags[@]}]: " choice </dev/tty || { echo ""; return 1; }
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#tags[@]} )); then
            echo "${tags[$(( choice-1 ))]}"
            return 0
        fi
        echo "  Invalid choice. Enter a number between 1 and ${#tags[@]}." >&2
    done
}

# _bash_radiolist <title> <prompt> <tag1> <item1> <on|off> ...  ->  stdout: chosen tag
# Items: tag item on|off  (repeating triplets)
_bash_radiolist() {
    local title="$1" prompt="$2"
    shift 2
    local -a tags items default_idx=()
    local default_tag=""
    local idx=0

    while [[ $# -ge 3 ]]; do
        tags+=("$1"); items+=("$2")
        [[ "$3" == "on" ]] && default_tag="$1" && default_idx=("$idx")
        shift 3; (( idx++ )) || true
    done

    _bash_separator >&2
    echo "  $title" >&2
    _bash_separator >&2
    echo "  $prompt" >&2
    echo "" >&2

    local i
    for (( i=0; i<${#tags[@]}; i++ )); do
        local marker=" "
        [[ "${tags[$i]}" == "$default_tag" ]] && marker="*"
        printf "  %2d) [%s] %s\n" $(( i+1 )) "$marker" "${items[$i]}" >&2
    done
    echo "  (* = current default)" >&2
    echo "" >&2

    local choice
    while true; do
        read -rp "  Enter number [1-${#tags[@]}] (Enter=default): " choice </dev/tty || { echo ""; return 1; }
        if [[ -z "$choice" ]]; then
            echo "$default_tag"
            return 0
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#tags[@]} )); then
            echo "${tags[$(( choice-1 ))]}"
            return 0
        fi
        echo "  Invalid choice. Enter a number between 1 and ${#tags[@]}." >&2
    done
}

# _bash_checklist <title> <prompt> <tag1> <item1> <on|off> ...  ->  stdout: space-sep tags
# Items: tag item on|off  (repeating triplets)
_bash_checklist() {
    local title="$1" prompt="$2"
    shift 2
    local -a tags items selected=()
    local idx=0

    while [[ $# -ge 3 ]]; do
        tags+=("$1"); items+=("$2")
        [[ "$3" == "on" ]] && selected+=("$idx")
        shift 3; (( idx++ )) || true
    done

    _bash_separator >&2
    echo "  $title" >&2
    _bash_separator >&2
    echo "  $prompt" >&2
    echo "  (Type numbers separated by spaces to toggle selection, then Enter)" >&2
    echo "" >&2

    local done_flag=false
    while [[ "$done_flag" == "false" ]]; do
        local i
        for (( i=0; i<${#tags[@]}; i++ )); do
            local mark=" "
            for s in "${selected[@]:-}"; do [[ "$s" == "$i" ]] && mark="X"; done
            printf "  %2d) [%s] %s\n" $(( i+1 )) "$mark" "${items[$i]}" >&2
        done
        echo "" >&2

        local input
        read -rp "  Toggle (space-sep numbers) or Enter to confirm: " input </dev/tty || { echo ""; return 1; }

        if [[ -z "$input" ]]; then
            done_flag=true
        else
            for num in $input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#tags[@]} )); then
                    local ti=$(( num - 1 ))
                    local already=false
                    local new_sel=()
                    for s in "${selected[@]:-}"; do
                        if [[ "$s" == "$ti" ]]; then already=true; else new_sel+=("$s"); fi
                    done
                    if [[ "$already" == "false" ]]; then
                        new_sel+=("$ti")
                    fi
                    selected=("${new_sel[@]:-}")
                fi
            done
        fi
    done

    local result=""
    for s in "${selected[@]:-}"; do
        result+="${tags[$s]} "
    done
    echo "${result% }"
}

# _bash_inputbox <title> <prompt> [default]  ->  stdout: entered text
_bash_inputbox() {
    local title="$1" prompt="$2" default="${3:-}"
    _bash_separator >&2
    echo "  $title" >&2
    _bash_separator >&2
    echo "  $prompt" >&2
    [[ -n "$default" ]] && echo "  (default: $default)" >&2
    echo "" >&2
    local value
    read -rp "  > " value </dev/tty || { echo ""; return 1; }
    if [[ -z "$value" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# _bash_passwordbox <title> <prompt>  ->  stdout: entered password
_bash_passwordbox() {
    local title="$1" prompt="$2"
    _bash_separator >&2
    echo "  $title" >&2
    _bash_separator >&2
    echo "  $prompt" >&2
    echo "" >&2
    local value
    read -rsp "  Password: " value </dev/tty || { echo ""; return 1; }
    echo "" >&2
    echo "$value"
}

# ===========================================================================
# PUBLIC HELPERS
# All text/title/prompt arguments are passed through strip_ansi() so that
# any ANSI colour codes captured from system commands are never rendered as
# literal escape sequences inside a dialog or bash fallback box.
#
# Each function dispatches to the dialog (_dlg) or bash fallback (_bash_*)
# implementation depending on UI_MODE.
# ===========================================================================

# ui_msgbox <title> <text>
ui_msgbox() {
    local title; title=$(strip_ansi "$1")
    local text;  text=$(strip_ansi "$2")
    if [[ "${UI_MODE:-dialog}" == "bash" ]]; then
        _bash_msgbox "$title" "$text"
    else
        read -r H W _ <<< "$(_dlg_dims)"
        _dlg --title "$title" --msgbox "$text" "$H" "$W"
    fi
}

# ui_yesno <title> <text>  ->  returns 0 for Yes, 1 for No
ui_yesno() {
    local title; title=$(strip_ansi "$1")
    local text;  text=$(strip_ansi "$2")
    if [[ "${UI_MODE:-dialog}" == "bash" ]]; then
        _bash_yesno "$title" "$text"
    else
        read -r H W _ <<< "$(_dlg_dims)"
        _dlg --title "$title" --yesno "$text" "$H" "$W"
    fi
}

# ui_menu <title> <prompt> <tag1> <item1> [tag2 item2 ...]  ->  stdout: chosen tag
ui_menu() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    shift 2
    if [[ "${UI_MODE:-dialog}" == "bash" ]]; then
        _bash_menu "$title" "$prompt" "$@"
    else
        read -r H W MH <<< "$(_dlg_dims)"
        _dlg --title "$title" --menu "$prompt" "$H" "$W" "$MH" "$@"
    fi
}

# ui_radiolist <title> <prompt> <tag1> <item1> <on|off> ...  ->  stdout: chosen tag
ui_radiolist() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    shift 2
    if [[ "${UI_MODE:-dialog}" == "bash" ]]; then
        _bash_radiolist "$title" "$prompt" "$@"
    else
        read -r H W MH <<< "$(_dlg_dims)"
        _dlg --title "$title" --radiolist "$prompt" "$H" "$W" "$MH" "$@"
    fi
}

# ui_checklist <title> <prompt> <tag1> <item1> <on|off> ...  ->  stdout: space-sep tags
ui_checklist() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    shift 2
    if [[ "${UI_MODE:-dialog}" == "bash" ]]; then
        _bash_checklist "$title" "$prompt" "$@"
    else
        read -r H W MH <<< "$(_dlg_dims)"
        _dlg --title "$title" --checklist "$prompt" "$H" "$W" "$MH" "$@"
    fi
}

# ui_inputbox <title> <prompt> [default]  ->  stdout: entered text
ui_inputbox() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    local default="${3:-}"
    if [[ "${UI_MODE:-dialog}" == "bash" ]]; then
        _bash_inputbox "$title" "$prompt" "$default"
    else
        read -r H W _ <<< "$(_dlg_dims)"
        _dlg --title "$title" --inputbox "$prompt" "$H" "$W" "$default"
    fi
}

# ui_passwordbox <title> <prompt>  ->  stdout: entered password
ui_passwordbox() {
    local title; title=$(strip_ansi "$1")
    local prompt; prompt=$(strip_ansi "$2")
    if [[ "${UI_MODE:-dialog}" == "bash" ]]; then
        _bash_passwordbox "$title" "$prompt"
    else
        read -r H W _ <<< "$(_dlg_dims)"
        _dlg --title "$title" --insecure --passwordbox "$prompt" "$H" "$W"
    fi
}

# ui_gauge_msg <title> <text> <pct>  (non-interactive progress; use with a loop)
ui_gauge_msg() {
    local title; title=$(strip_ansi "$1")
    local text;  text=$(strip_ansi "$2")
    local pct="$3"
    if [[ "${UI_MODE:-dialog}" == "bash" ]]; then
        echo "  [$pct%] $title: $text" >&2
    else
        read -r H W _ <<< "$(_dlg_dims)"
        echo "$pct" | dialog --backtitle "$(strip_ansi "${UI_BACKTITLE:-ArchInstall Framework}")" \
            --title "$title" --gauge "$text" 7 "$W" "$pct"
    fi
}

# ---------------------------------------------------------------------------
# Dependency check - call before starting the installer
# ---------------------------------------------------------------------------
require_tools() {
    # When dialog is not installed, automatically fall back to bash UI mode.
    # This lets you test and debug the installer on a minimal system without
    # needing to install the dialog package first.
    if ! command -v dialog &>/dev/null; then
        if [[ "${UI_MODE:-}" == "dialog" ]]; then
            # Caller explicitly required dialog — exit with a helpful message.
            echo "ERROR: 'dialog' is not installed but UI_MODE=dialog was requested." >&2
            echo "       Install it with:" >&2
            echo "         pacman -Sy --needed dialog" >&2
            exit 1
        fi
        UI_MODE=bash
        echo "[INFO] 'dialog' not found — running in bash fallback mode (UI_MODE=bash)." >&2
        echo "       Install dialog for the full TUI experience:" >&2
        echo "         pacman -Sy --needed dialog" >&2
    fi
    export UI_MODE

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
    if [[ "$UI_MODE" == "dialog" ]] && ! tput clear &>/dev/null; then
        if [[ -t 0 ]]; then
            export TERM=linux
        else
            export TERM=xterm-256color
        fi
    fi
}
