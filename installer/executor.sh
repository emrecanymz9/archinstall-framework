#!/usr/bin/env bash
# installer/executor.sh - logging, command execution, arch-chroot wrapper
set -Eeuo pipefail

LOG_FILE="${LOG_FILE:-/tmp/archinstall.log}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE" >&2; }
log_step()  { printf '\n========================================\n  STEP: %s\n========================================\n' "$*" >> "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# run_cmd - run a command, log it, stream output to log, die on failure
# ---------------------------------------------------------------------------
run_cmd() {
    log_info "RUN: $*"
    if ! "$@" >> "$LOG_FILE" 2>&1; then
        log_error "Command failed: $*"
        log_error "See $LOG_FILE for details"
        return 1
    fi
}

# run_cmd_interactive - like run_cmd but also shows output on screen
run_cmd_interactive() {
    log_info "RUN: $*"
    if ! "$@" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Command failed: $*"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# chroot_run - run a command inside the installed system
# Usage: chroot_run "command with args"   (string is passed to bash -c)
# ---------------------------------------------------------------------------
MOUNT_POINT="${MOUNT_POINT:-/mnt}"

chroot_run() {
    local cmd="$1"
    log_info "CHROOT: $cmd"
    if ! arch-chroot "$MOUNT_POINT" \
           /usr/bin/env -i \
           HOME=/root \
           PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
           TERM="${TERM:-linux}" \
           bash -c "$cmd" >> "$LOG_FILE" 2>&1; then
        log_error "chroot command failed: $cmd"
        return 1
    fi
}

# chroot_run_interactive - shows output on screen (for pacstrap-like tasks)
chroot_run_interactive() {
    local cmd="$1"
    log_info "CHROOT(interactive): $cmd"
    arch-chroot "$MOUNT_POINT" \
        /usr/bin/env -i \
        HOME=/root \
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        TERM="${TERM:-linux}" \
        bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# die - print error and exit
# ---------------------------------------------------------------------------
die() {
    log_error "$*"
    exit 1
}
