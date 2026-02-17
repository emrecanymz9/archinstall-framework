set -x

select_disk() {

    local disks
    disks=$(list_install_disks)

    if [[ -z "$disks" ]]; then
        dialog --msgbox "No installable disks detected." 10 50
        return 1
    fi

    local menu_items=()

    while IFS="|" read -r name size model; do
        menu_items+=("$name" "$size - $model")
    done <<< "$disks"

    local tmpfile
    tmpfile=$(mktemp)

    dialog \
        --clear \
        --backtitle "ArchInstall Framework 2026" \
        --title "Disk Selection" \
        --menu "Select installation disk:" \
        20 70 10 \
        "${menu_items[@]}" \
        2> "$tmpfile"

    local exit_status=$?

    if [[ $exit_status -ne 0 ]]; then
        rm -f "$tmpfile"
        return 1
    fi

    local choice
    choice=$(<"$tmpfile")
    rm -f "$tmpfile"

    if [[ -z "$choice" ]]; then
        return 1
    fi

    export TARGET_DISK="$choice"
    return 0
}
