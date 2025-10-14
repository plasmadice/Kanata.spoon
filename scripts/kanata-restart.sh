#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Restart Kanata
# @raycast.mode inline

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author plasmadice
# @raycast.authorURL https://github.com/plasmadice

# Check for quiet flag
QUIET_MODE=false
if [[ "$1" == "--quiet" ]]; then
    QUIET_MODE=true
fi

# Retrieve password from keychain
pw_name="supa"
pw_account=$(id -un)

if ! cli_password=$(security find-generic-password -w -s "$pw_name" -a "$pw_account" 2>&1); then
  echo "❌ Could not get password (error $?)"
  exit 1
fi

# Note about Karabiner
echo "Note: Make sure Karabiner Elements app and menu bar item are quit before using Kanata."

# Find Kanata binary
KANATA_BIN=$(command -v kanata)
if [ -z "$KANATA_BIN" ]; then
    echo "❌ Kanata binary not found. Please run the install script first."
    exit 1
fi

# Check if plist exists, if not create it
if [ ! -f "/Library/LaunchDaemons/com.example.kanata.plist" ]; then
    echo "⚠️  Kanata plist not found. Creating it now..."
    
    # Create log directory
    echo "$cli_password" | sudo -S mkdir -p /Library/Logs/Kanata
    echo "$cli_password" | sudo -S chown root:wheel /Library/Logs/Kanata
    
    # Create plist file
    if ! echo "$cli_password" | sudo -S tee /Library/LaunchDaemons/com.example.kanata.plist >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.example.kanata</string>
  <key>ProgramArguments</key><array>
    <string>${KANATA_BIN}</string>
    <string>--nodelay</string>
    <string>-c</string><string>${HOME}/.config/kanata/kanata.kbd</string>
    <string>--port</string><string>10000</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key>
  <string>/Library/Logs/Kanata/kanata.out.log</string>
  <key>StandardErrorPath</key>
  <string>/Library/Logs/Kanata/kanata.err.log</string>
</dict></plist>
EOF
    then
        echo "❌ Failed to create Kanata plist file"
        exit 1
    fi
    
    # Set ownership and permissions
    if ! echo "$cli_password" | sudo -S chown root:wheel /Library/LaunchDaemons/com.example.kanata.plist; then
        echo "❌ Failed to set ownership for Kanata plist"
        exit 1
    fi
    
    if ! echo "$cli_password" | sudo -S chmod 644 /Library/LaunchDaemons/com.example.kanata.plist; then
        echo "❌ Failed to set permissions for Kanata plist"
        exit 1
    fi
    
    echo "✅ Kanata plist created successfully!"
fi

# Stop Kanata service
if [ "$QUIET_MODE" = false ]; then
    echo "Stopping Kanata service..."
fi
echo "$cli_password" | sudo -S launchctl bootout system /Library/LaunchDaemons/com.example.kanata.plist 2>/dev/null || true

# Start Kanata service
if [ "$QUIET_MODE" = false ]; then
    echo "Starting Kanata service..."
fi
error_output=$(echo "$cli_password" | sudo -S launchctl bootstrap system /Library/LaunchDaemons/com.example.kanata.plist 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ]; then
  if [ "$QUIET_MODE" = false ]; then
    echo "✅ Kanata restarted successfully!"
  fi
elif echo "$error_output" | grep -q "Already loaded"; then
  if [ "$QUIET_MODE" = false ]; then
    echo "✅ Kanata restarted successfully!"
  fi
else
  echo "❌ Failed to restart Kanata:"
  echo "$error_output"
  exit 1
fi

# Start Hammerspoon Kanata monitoring service
if [ "$QUIET_MODE" = false ]; then
    echo "Starting Hammerspoon Kanata monitoring service..."
fi
if [ "$QUIET_MODE" = true ]; then
    # Use suppressLog parameter when in quiet mode
    if open -g "hammerspoon://kanata?action=start&suppressLog=true" 2>/dev/null; then
        # Silent success
        true
    else
        # Silent failure
        true
    fi
else
    if open -g "hammerspoon://kanata?action=start" 2>/dev/null; then
        echo "✅ Hammerspoon Kanata monitoring service started"
    else
        echo "⚠️  Failed to start Hammerspoon monitoring service - it may not be available"
    fi
fi