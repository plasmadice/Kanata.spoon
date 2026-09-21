#!/usr/bin/env bash

# Machine-readable progress consumed by Kanata.spoon's hs.task stream callback.
# Human-readable output remains alongside these records for Terminal use.
progress() {
    local percent="$1"
    shift
    printf 'KANATA_PROGRESS=%s:%s\n' "$percent" "$*"
}
