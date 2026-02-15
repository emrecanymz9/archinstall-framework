#!/usr/bin/env bash

CRYPT_NAME="cryptroot"

setup_luks() {

    if [[ -z "$PLAN_ROOT_PART" ]]; then
        echo "No root partition planned"
        exit 1
    fi

    echo "Formatting LUKS2 on $PLAN_ROOT_PART"

    cryptsetup luksFormat --type luks2 "$PLAN_ROOT_PART"

    cryptsetup open "$PLAN_ROOT_PART" "$CRYPT_NAME"

    LUKS_DEVICE="/dev/mapper/$CRYPT_NAME"
}
