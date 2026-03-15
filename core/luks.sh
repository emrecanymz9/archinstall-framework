#!/usr/bin/env bash
# core/luks.sh – encryption selection and LUKS2 setup
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# ask_encryption  →  sets ENCRYPTION (true/false), saves to state
# ---------------------------------------------------------------------------
ask_encryption() {
    local choice
    choice=$(ui_radiolist "Disk Encryption" \
        "Choose whether to encrypt the root partition with LUKS2.\n\n\
Encrypted: your data is protected if the disk is stolen.\n\
  You will enter a passphrase at every boot.\n\n\
Unencrypted: no passphrase at boot, simpler setup.\n\
  (You can add encryption later manually, but it requires data migration.)" \
        "luks2"       "LUKS2 Encrypted root (recommended)"   "on" \
        "unencrypted" "Unencrypted"                          "off" \
    ) || { clear; exit 0; }

    if [[ "$choice" == "luks2" ]]; then
        ENCRYPTION=true
        set_state "encryption" "true"
    else
        ENCRYPTION=false
        set_state "encryption" "false"
    fi
    log_info "Encryption: $ENCRYPTION"
}

# ---------------------------------------------------------------------------
# setup_luks  →  formats ROOT_PART with LUKS2, opens it
# Sets ROOT_MAPPED to /dev/mapper/<luks_name>
# ---------------------------------------------------------------------------
setup_luks() {
    local part="${ROOT_PART}"
    local luks_name="cryptroot"
    set_state_str "luks_name" "$luks_name"
    log_step "Setting up LUKS2 on $part"

    # Ask for passphrase (with confirmation)
    local pass1 pass2
    while true; do
        pass1=$(ui_passwordbox "LUKS2 Passphrase" \
            "Enter encryption passphrase:\n(This passphrase unlocks your disk at every boot)") \
            || { clear; exit 0; }
        pass2=$(ui_passwordbox "LUKS2 Passphrase – Confirm" \
            "Re-enter the passphrase to confirm:") \
            || { clear; exit 0; }
        if [[ "$pass1" == "$pass2" ]]; then
            break
        fi
        ui_msgbox "Passphrase Mismatch" "Passphrases do not match. Please try again."
    done

    log_info "Formatting $part as LUKS2..."
    echo "$pass1" | run_cmd cryptsetup luksFormat \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha256 \
        --iter-time 3000 \
        --batch-mode \
        --key-file=- \
        "$part"

    log_info "Opening LUKS2 container as $luks_name..."
    echo "$pass1" | run_cmd cryptsetup open --key-file=- "$part" "$luks_name"

    ROOT_MAPPED="/dev/mapper/${luks_name}"
    set_state_str "root_mapped" "$ROOT_MAPPED"

    # Store LUKS UUID for mkinitcpio / bootloader
    LUKS_UUID=$(blkid -s UUID -o value "$part")
    log_info "LUKS UUID: $LUKS_UUID"
}

# ---------------------------------------------------------------------------
# setup_noencrypt  →  ROOT_MAPPED = ROOT_PART (no encryption)
# ---------------------------------------------------------------------------
setup_noencrypt() {
    ROOT_MAPPED="$ROOT_PART"
    LUKS_UUID=""
    set_state_str "root_mapped" "$ROOT_MAPPED"
    log_info "No encryption; ROOT_MAPPED=$ROOT_MAPPED"
}