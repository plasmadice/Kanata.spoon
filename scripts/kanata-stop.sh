#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop Kanata
# @raycast.mode inline

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author plasmadice
# @raycast.authorURL https://github.com/plasmadice

# Retrieve password from keychain
pw_name="supa"
pw_account=$(id -un)

if ! cli_password=$(security find-generic-password -w -s "$pw_name" -a "$pw_account" 2>&1); then
  echo "❌ Could not get password (error $?)"
  exit 1
fi

# Find Kanata binary (for verification)
KANATA_BIN=$(command -v kanata)
if [ -z "$KANATA_BIN" ]; then
    echo "⚠️  Kanata binary not found, but continuing with service stop"
fi

# Use LaunchDaemon (system-level) - required for Virtual HID server socket access
PLIST_PATH="/Library/LaunchDaemons/com.example.kanata.plist"

# Stop Kanata service (try both LaunchAgent and LaunchDaemon)
echo "Stopping Kanata service..."
# Try to stop LaunchAgent first (if it exists)
launchctl bootout gui/$(id -u)/com.example.kanata 2>/dev/null || true
# Stop LaunchDaemon
error_output=$(echo "$cli_password" | sudo -S launchctl bootout system "${PLIST_PATH}" 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ]; then
  echo "✅ Kanata service stopped successfully!"
elif echo "$error_output" | grep -q "Could not find service\|No such process"; then
  echo "⚠️  Kanata service is not running!"
else
  echo "❌ Failed to stop Kanata service:"
  echo "$error_output"
  exit 1
fi

# Remove plist file
echo "Removing Kanata plist file..."
if [ -f "${PLIST_PATH}" ]; then
    if echo "$cli_password" | sudo -S rm -f "${PLIST_PATH}"; then
        echo "✅ Kanata plist file removed successfully!"
    else
        echo "❌ Failed to remove Kanata plist file"
        exit 1
    fi
else
    echo "⚠️  Kanata plist file not found"
fi

# Stop Hammerspoon Kanata monitoring service
echo "Stopping Hammerspoon Kanata monitoring service..."
if open -g "hammerspoon://kanata?action=stop" 2>/dev/null; then
    echo "✅ Hammerspoon Kanata monitoring service stopped"
else
    echo "⚠️  Failed to stop Hammerspoon monitoring service - it may not be available"
fi
