#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Install/Restart Kanata
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🎹

# Documentation:
# @raycast.author plasmadice
# @raycast.authorURL https://github.com/plasmadice

# Installs Kanata via Homebrew and sets up LaunchDaemon
# Requires Karabiner Elements to be installed and configured first

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
KANATA_CONFIG="${HOME}/.config/kanata/kanata.kbd"
KANATA_PORT=10000
PLIST_DIR="/Library/LaunchDaemons"
###################################

# 1. Check if Karabiner Elements is installed
debug "Checking for Karabiner Elements"
if [ ! -d "/Applications/Karabiner-Elements.app" ]; then
    error_exit "Karabiner Elements is not installed!"
    echo "Please install Karabiner Elements first from:"
    echo "https://karabiner-elements.pqrs.org/"
    echo
    echo "After installation, make sure to:"
    echo "1. Enable all required permissions in System Settings"
    echo "2. Quit Karabiner Elements app AND the menu bar item"
    echo "3. Then run this script again"
    exit 1
fi
success "Karabiner Elements found"

# 2. Note about Karabiner
debug "Reminding user about Karabiner requirements"
echo "Note: Make sure Karabiner Elements app and menu bar item are quit before using Kanata."

# 3. Install Kanata via Homebrew if not present
debug "Checking if Kanata is installed via Homebrew"
if brew list kanata >/dev/null 2>&1; then
    debug "Kanata is already installed via brew"
    success "Kanata already installed"
else
    debug "Kanata not found in brew, installing"
    if ! brew install kanata; then
        error_exit "Failed to install Kanata via Homebrew"
    fi
    success "Kanata installed successfully"
fi

# Find Kanata binary - prioritize brew location
debug "Searching for Kanata binary"
KANATA_BIN=""
if command -v kanata >/dev/null 2>&1; then
    KANATA_BIN=$(command -v kanata)
    debug "Found kanata in PATH: $KANATA_BIN"
elif [ -f "/opt/homebrew/bin/kanata" ]; then
    KANATA_BIN="/opt/homebrew/bin/kanata"
    debug "Found kanata at /opt/homebrew/bin/kanata"
elif [ -f "/usr/local/bin/kanata" ]; then
    KANATA_BIN="/usr/local/bin/kanata"
    debug "Found kanata at /usr/local/bin/kanata"
else
    debug "Kanata not found in standard locations, searching brew cellar"
    # Search in brew cellar directories
    CELLAR_PATHS=("/opt/homebrew/Cellar/kanata" "/usr/local/Cellar/kanata")
    for cellar_path in "${CELLAR_PATHS[@]}"; do
        if [ -d "$cellar_path" ]; then
            debug "Searching in $cellar_path"
            found_binary=$(find "$cellar_path" -name "kanata" -type f 2>/dev/null | head -1)
            if [ -n "$found_binary" ]; then
                KANATA_BIN="$found_binary"
                debug "Found kanata in cellar: $KANATA_BIN"
                break
            fi
        fi
    done
    
    if [ -z "$KANATA_BIN" ]; then
        debug "Kanata binary not found anywhere, checking brew info"
        brew info kanata || true
        error_exit "Kanata binary not found in expected brew locations"
    fi
fi
debug "Using Kanata binary at: $KANATA_BIN"

# 4. Create log directory
debug "Creating log directory"
if ! echo "$cli_password" | sudo -S mkdir -p /Library/Logs/Kanata; then
    error_exit "Failed to create log directory"
fi
if ! echo "$cli_password" | sudo -S chown root:wheel /Library/Logs/Kanata; then
    error_exit "Failed to set ownership for log directory"
fi
success "Log directory created and configured"

# 5. Write Kanata plist file
debug "Creating Kanata plist file"
debug "Config at: ${KANATA_CONFIG}"
debug "Binary at: ${KANATA_BIN}"
if ! echo "$cli_password" | sudo -S tee "${PLIST_DIR}/com.example.kanata.plist" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.example.kanata</string>
  <key>ProgramArguments</key><array>
    <string>${KANATA_BIN}</string>
    <string>--nodelay</string>
    <string>-c</string><string>${KANATA_CONFIG}</string>
    <string>--port</string><string>${KANATA_PORT}</string>
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
    error_exit "Failed to create Kanata plist file"
fi
success "Kanata plist file created"


if ! echo "$cli_password" | sudo -S chown root:wheel "${PLIST_DIR}/com.example.kanata.plist"; then
    error_exit "Failed to set ownership for Kanata plist"
fi

if ! echo "$cli_password" | sudo -S chmod 644 "${PLIST_DIR}/com.example.kanata.plist"; then
    error_exit "Failed to set permissions for Kanata plist"
fi

success "Kanata plist permissions set"

# 6. Stop existing services
debug "Stopping existing services"
echo "$cli_password" | sudo -S launchctl bootout system "${PLIST_DIR}/com.example.kanata.plist" 2>/dev/null || debug "Kanata service not running or already stopped"
success "Existing services stopped"

# 7. Start services
debug "Starting services"

debug "Starting Kanata service"
debug "launchctl bootstrap system ${PLIST_DIR}/com.example.kanata.plist"
if ! echo "$cli_password" | sudo -S launchctl bootstrap system "${PLIST_DIR}/com.example.kanata.plist"; then
    error_exit "Failed to bootstrap Kanata service"
fi
if ! echo "$cli_password" | sudo -S launchctl enable system/com.example.kanata; then
    error_exit "Failed to enable Kanata service"
fi
success "Kanata service started and enabled"

# 8. Start Hammerspoon Kanata monitoring service
debug "Starting Hammerspoon Kanata monitoring service"
if open -g "hammerspoon://kanata?action=start" 2>/dev/null; then
    success "Hammerspoon Kanata monitoring service started"
else
    warning "Failed to start Hammerspoon monitoring service - it may not be available"
fi
