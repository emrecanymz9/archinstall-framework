#!/usr/bin/env bash

STATE_FILE="config/state.json"

init_state() {
    mkdir -p config
    cat > "$STATE_FILE" <<EOF
{
  "boot_mode": "",
  "target_disk": "",
  "partition_strategy": "",
  "encryption": false,
  "filesystem": "btrfs",
  "features": {
    "zram": true,
    "pipewire": true,
    "secureboot": true,
    "gaming": true,
    "devtools": true,
    "virtualization": true
  }
}
EOF
}

set_state() {
    local key=$1
    local value=$2
    jq ".$key = $value" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"
}

get_state() {
    local key=$1
    jq -r ".$key" "$STATE_FILE"
}
