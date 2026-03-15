#!/usr/bin/env bash
# core/state.sh – JSON state management via jq
set -Eeuo pipefail

# FRAMEWORK_ROOT must be set before sourcing this file
STATE_FILE="${FRAMEWORK_ROOT}/config/state.json"

# ---------------------------------------------------------------------------
# init_state – write the initial empty state template
# ---------------------------------------------------------------------------
init_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" <<'EOF'
{
  "boot_mode":         "",
  "install_mode":      "",
  "target_disk":       "",
  "efi_partition":     "",
  "root_partition":    "",
  "root_mapped":       "",
  "partition_table":   "",
  "encryption":        false,
  "luks_name":         "cryptroot",
  "filesystem":        "btrfs",
  "bootloader":        "limine",
  "hostname":          "",
  "username":          "",
  "root_locked":       true,
  "microcode":         "",
  "free_seg_start":    "",
  "free_seg_end":      "",
  "phase1_done":       false,
  "phase2_done":       false
}
EOF
}

# ---------------------------------------------------------------------------
# set_state <dotted.key> <json-value>
# set_state "hostname" '"my-arch"'
# set_state "encryption" "true"
# ---------------------------------------------------------------------------
set_state() {
    local key="$1" value="$2" tmp
    tmp=$(mktemp)
    jq --argjson v "$value" ".$key = \$v" "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# set_state_str <key> <plain-string>   (wraps string in JSON quotes for you)
set_state_str() {
    local key="$1" value="$2" tmp
    tmp=$(mktemp)
    jq --arg v "$value" ".$key = \$v" "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# get_state <key>  →  stdout: raw JSON value (strings already unquoted by -r)
# ---------------------------------------------------------------------------
get_state() {
    jq -r ".$1" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# state_is_done <phase>  →  returns 0 if true, 1 otherwise
# ---------------------------------------------------------------------------
state_is_done() {
    [[ "$(get_state "$1")" == "true" ]]
}

# ---------------------------------------------------------------------------
# mark_done <phase>  e.g. mark_done phase1_done
# ---------------------------------------------------------------------------
mark_done() {
    set_state "$1" "true"
}
