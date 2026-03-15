#!/usr/bin/env bash
# postinstall/install.sh – Phase 2 orchestrator (Post Install)
# Runs automatically on first boot via systemd, or manually by the user.
set -Eeuo pipefail

FRAMEWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FRAMEWORK_ROOT
export LOG_FILE="${LOG_FILE:-/var/log/archinstall-phase2.log}"
export UI_BACKTITLE="ArchInstall Framework — Post Install"

source "$FRAMEWORK_ROOT/installer/ui.sh"
source "$FRAMEWORK_ROOT/installer/state.sh"
source "$FRAMEWORK_ROOT/installer/executor.sh"

# ---------------------------------------------------------------------------
# Must run as root
# ---------------------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Post Install must run as root (systemd service runs it as root)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Check if already done (idempotency guard)
# ---------------------------------------------------------------------------
if [[ -f /var/lib/archinstall/phase2-done ]]; then
    log_info "Post Install already completed. Remove /var/lib/archinstall/phase2-done to re-run."
    exit 0
fi

log_info "ArchInstall Post Install starting. Log: $LOG_FILE"

# ---------------------------------------------------------------------------
# Run KDE desktop post-install flow
# (Future: present a desktop-environment selection menu here)
# ---------------------------------------------------------------------------
source "$FRAMEWORK_ROOT/postinstall/desktops/kde.sh"
main_kde

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
mark_done "phase2_done"

log_info "Post Install complete."

ui_msgbox "Post Install Complete!" \
"KDE Plasma 6 and all modules have been installed!

Your system is ready. Please reboot to start using KDE.

Log file: $LOG_FILE

  systemctl reboot"
