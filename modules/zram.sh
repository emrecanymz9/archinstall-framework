#!/usr/bin/env bash
# modules/zram.sh – ZRAM configuration and verification
set -Eeuo pipefail

configure_zram() {
    log_info "Configuring ZRAM..."

    # zram-generator config
    cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
EOF

    systemctl daemon-reload
    systemctl start systemd-zram-setup@zram0.service 2>/dev/null || true

    # Verify
    if [[ -b /dev/zram0 ]]; then
        log_info "ZRAM device /dev/zram0 active."
        local zram_info
        zram_info=$(swapon --show=NAME,SIZE,USED,PRIO 2>/dev/null | grep zram || echo "zram0 not in swapon yet")
        log_info "ZRAM status: $zram_info"
    else
        log_warn "ZRAM device not yet active; it will activate on next boot."
    fi

    # Swappiness tuning for ZRAM:
    # Values above 100 are valid for ZRAM. They instruct the kernel to prefer
    # ZRAM swap over keeping anonymous pages in RAM, improving memory utilization.
    # See: https://www.kernel.org/doc/html/latest/admin-guide/sysctl/vm.html
    cat > /etc/sysctl.d/99-zram.conf <<'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF

    log_info "ZRAM configured. Swappiness tuned for ZRAM usage."
}