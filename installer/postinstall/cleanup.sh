#!/usr/bin/env bash

postinstall_cleanup_chroot_snippet() {
	cat <<'EOF'
log_chroot_step "Cleaning installer temp files"
rm -f /tmp/archinstall-* /tmp/install_config.json 2>/dev/null || true
EOF
}
