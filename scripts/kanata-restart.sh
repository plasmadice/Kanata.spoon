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

# Check Karabiner DriverKit version
check_driver_version() {
    local required_version="6.2.0"
    local driver_version=""
    
    # Try to get version from Info.plist (most reliable)
    local plist_path=$(find "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice" -name "Info.plist" 2>/dev/null | head -1)
    if [ -n "$plist_path" ]; then
        driver_version=$(defaults read "$plist_path" CFBundleShortVersionString 2>/dev/null || echo "")
    fi
    
    if [ -z "$driver_version" ]; then
        echo "⚠️  Could not determine Karabiner DriverKit version"
        echo "   Kanata 1.10.0 requires DriverKit v6.2.0 or newer"
        return 1
    fi
    
    # Compare versions
    local required_major=$(echo "$required_version" | cut -d'.' -f1)
    local required_minor=$(echo "$required_version" | cut -d'.' -f2)
    local driver_major=$(echo "$driver_version" | cut -d'.' -f1)
    local driver_minor=$(echo "$driver_version" | cut -d'.' -f2)
    
    if [ "$driver_major" -lt "$required_major" ] || \
       ([ "$driver_major" -eq "$required_major" ] && [ "$driver_minor" -lt "$(echo $required_version | cut -d'.' -f2)" ]); then
        echo "❌ Karabiner DriverKit version $driver_version is too old!"
        echo "   Kanata 1.10.0 requires v6.2.0 or newer"
        echo "   Please update Karabiner Elements from: https://karabiner-elements.pqrs.org/"
        return 1
    fi
    
    if [ "$QUIET_MODE" = false ]; then
        echo "✅ Karabiner DriverKit v$driver_version is compatible"
    fi
    return 0
}

if ! check_driver_version; then
    if [ "$QUIET_MODE" = false ]; then
        echo ""
        echo "Continuing anyway, but Kanata may not work correctly..."
        echo ""
    fi
fi

# Find Kanata binary
KANATA_BIN=$(command -v kanata)
if [ -z "$KANATA_BIN" ]; then
    echo "❌ Kanata binary not found. Please run the install script first."
    exit 1
fi

# Use LaunchDaemon (system-level) - required for Virtual HID server socket access
# Kanata 1.10.0 needs root access to /Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server
PLIST_DIR="/Library/LaunchDaemons"
PLIST_PATH="${PLIST_DIR}/com.example.kanata.plist"
LOG_DIR="/Library/Logs/Kanata"

# Create log directory
echo "$cli_password" | sudo -S mkdir -p "${LOG_DIR}" 2>/dev/null || true
echo "$cli_password" | sudo -S chown root:wheel "${LOG_DIR}" 2>/dev/null || true

# Check if plist exists, if not create it
if [ ! -f "${PLIST_PATH}" ]; then
    echo "⚠️  Kanata plist not found. Creating it now..."
    
    # Create plist file (system-level, requires sudo)
    if ! echo "$cli_password" | sudo -S tee "${PLIST_PATH}" >/dev/null <<EOF
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
  <string>${LOG_DIR}/kanata.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/kanata.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict></plist>
EOF
    then
        echo "❌ Failed to create Kanata plist file"
        exit 1
    fi
    
    # Set ownership and permissions
    echo "$cli_password" | sudo -S chown root:wheel "${PLIST_PATH}" 2>/dev/null || true
    echo "$cli_password" | sudo -S chmod 644 "${PLIST_PATH}" 2>/dev/null || true
    
    echo "✅ Kanata plist created successfully!"
fi

# Stop Kanata service (try both LaunchAgent and LaunchDaemon)
if [ "$QUIET_MODE" = false ]; then
    echo "Stopping Kanata service..."
fi
# Try to stop old LaunchAgent first
launchctl bootout gui/$(id -u)/com.example.kanata 2>/dev/null || true
# Stop LaunchDaemon
stop_output=$(echo "$cli_password" | sudo -S launchctl bootout system "${PLIST_PATH}" 2>&1)
stop_code=$?

# Wait a moment for the service to fully stop
sleep 1

# Start Kanata service (system-level, requires sudo)
if [ "$QUIET_MODE" = false ]; then
    echo "Starting Kanata service..."
fi
error_output=$(echo "$cli_password" | sudo -S launchctl bootstrap system "${PLIST_PATH}" 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ]; then
  if [ "$QUIET_MODE" = false ]; then
    echo "✅ Kanata restarted successfully!"
  fi
elif echo "$error_output" | grep -q "Already loaded\|service already loaded\|already bootstrapped"; then
  if [ "$QUIET_MODE" = false ]; then
    echo "✅ Kanata service already running"
  fi
else
  echo "❌ Failed to restart Kanata (exit code: $exit_code):"
  echo "$error_output"
  if [ "$QUIET_MODE" = false ]; then
    echo "Stop output: $stop_output (exit code: $stop_code)"
    echo ""
    echo "Note: Make sure Kanata has Input Monitoring permissions in:"
    echo "System Settings > Privacy & Security > Input Monitoring"
  fi
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
