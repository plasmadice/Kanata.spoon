#!/usr/bin/env bash

# Run a command as root. Prefer the existing "supa" login-keychain item so
# Hammerspoon actions remain non-interactive. Fall back to normal sudo in a
# terminal or the standard macOS administrator prompt for GUI callers.
run_as_root() {
    local admin_password

    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif admin_password=$(
        security find-generic-password -w -s "supa" -a "$(id -un)" 2>/dev/null
    ); then
        printf '%s\n' "$admin_password" | sudo -S -p "" "$@"
    elif [ -t 0 ]; then
        sudo "$@"
    else
        /usr/bin/osascript - "$@" <<'APPLESCRIPT'
on run argv
    set commandText to ""
    repeat with argumentText in argv
        set commandText to commandText & quoted form of (argumentText as text) & " "
    end repeat
    return do shell script commandText with administrator privileges
end run
APPLESCRIPT
    fi
}
