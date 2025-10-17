#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Cleanup Kanata & Karabiner
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🧹

# Documentation:
# @raycast.author plasmadice
# @raycast.authorURL https://github.com/plasmadice

# Cleanup script that uninstalls Kanata and removes all Karabiner services and plist files

set -euo pipefail

# Enhanced error handling and debugging
debug() {
    echo "🔍 DEBUG: $1" >&2
}

error_exit() {
    echo "❌ ERROR: $1" >&2
    exit 1
}

success() {
    echo "✅ $1"
}

warning() {
    echo "⚠️  $1"
}

# Retrieve password from keychain
debug "Starting password retrieval from keychain"
pw_name="supa" # name of the password in the keychain
pw_account=$(id -un) # current username e.g. "viper"
debug "Looking for password with name: $pw_name, account: $pw_account"

if ! cli_password=$(security find-generic-password -w -s "$pw_name" -a "$pw_account" 2>&1); then
  error_exit "Could not get password (error $?)"
  echo "Please add your password to keychain with:"
  echo "security add-generic-password -s 'supa' -a '$(id -un)' -w 'your_password'"
  exit 1
fi
debug "Password retrieved successfully"

#### CONFIGURATION ####
PLIST_DIR="/Library/LaunchDaemons"
###################################

echo "🧹 Starting cleanup of Kanata and Karabiner services..."

# 1. Stop Hammerspoon Kanata monitoring service
debug "Stopping Hammerspoon Kanata monitoring service"
if open -g "hammerspoon://kanata?action=stop" 2>/dev/null; then
    success "Hammerspoon Kanata monitoring service stopped"
else
    warning "Failed to stop Hammerspoon monitoring service - it may not be available"
fi

# 2. Stop Kanata service
debug "Stopping Kanata service"
echo "$cli_password" | sudo -S launchctl bootout system "${PLIST_DIR}/com.example.kanata.plist" 2>/dev/null || debug "Kanata service not running or already stopped"
success "Kanata service stopped"

# 3. Remove Kanata plist file
debug "Removing Kanata plist file"
if [ -f "${PLIST_DIR}/com.example.kanata.plist" ]; then
    if echo "$cli_password" | sudo -S rm -f "${PLIST_DIR}/com.example.kanata.plist"; then
        success "Removed Kanata plist file"
    else
        warning "Failed to remove Kanata plist file"
    fi
else
    debug "Kanata plist file not found, skipping"
fi

# 4. Kill any running Kanata processes
debug "Killing any running Kanata processes"
pkill -f "kanata" 2>/dev/null || debug "No running Kanata processes found"

# 5. Uninstall Kanata via Homebrew
debug "Uninstalling Kanata via Homebrew"
if command -v brew >/dev/null 2>&1; then
    if brew list kanata >/dev/null 2>&1; then
        debug "Kanata found in Homebrew, uninstalling"
        if brew uninstall kanata; then
            success "Kanata uninstalled from Homebrew"
        else
            warning "Failed to uninstall Kanata from Homebrew"
        fi
    else
        debug "Kanata not found in Homebrew"
    fi
else
    debug "Homebrew not found, skipping kanata uninstall"
fi

# 6. Remove log directory
debug "Removing log directory"
if [ -d "/Library/Logs/Kanata" ]; then
    if echo "$cli_password" | sudo -S rm -rf "/Library/Logs/Kanata"; then
        success "Removed log directory"
    else
        warning "Failed to remove log directory"
    fi
else
    debug "Log directory not found"
fi

# 7. Note about Karabiner Elements
echo
echo "ℹ️  Note: This cleanup only removes Kanata."
echo "Karabiner Elements is left installed as it may be used for other purposes."

# 8. Clean up any remaining files
debug "Cleaning up remaining files"

# Remove kanata config directory if empty
if [ -d "${HOME}/.config/kanata" ]; then
    if [ -z "$(ls -A "${HOME}/.config/kanata" 2>/dev/null)" ]; then
        debug "Removing empty kanata config directory"
        rm -rf "${HOME}/.config/kanata"
        success "Removed empty kanata config directory"
    else
        debug "Kanata config directory not empty, keeping it"
    fi
fi

# 9. Final verification
debug "Performing final verification"
remaining_services=$(echo "$cli_password" | sudo -S launchctl list | grep -E "kanata" || true)
if [ -n "$remaining_services" ]; then
    warning "Some Kanata services may still be running:"
    echo "$remaining_services"
else
    success "No remaining Kanata services found"
fi

# Check if kanata binary still exists
if command -v kanata >/dev/null 2>&1; then
    warning "Kanata binary still found in PATH: $(command -v kanata)"
else
    success "Kanata binary not found in PATH"
fi

echo
echo "🎉 Cleanup completed!"
echo
echo "Summary of actions taken:"
echo "✅ Stopped Kanata service"
echo "✅ Removed Kanata plist file"
echo "✅ Killed running Kanata processes"
echo "✅ Uninstalled Kanata from Homebrew"
echo "✅ Removed log directory"
echo "✅ Cleaned up remaining files"
echo
echo "Note: You may need to manually remove Kanata from:"
echo "- System Preferences > Security & Privacy > Privacy > Accessibility"
echo "- System Preferences > Security & Privacy > Privacy > Input Monitoring"
