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

warning() {
    echo "⚠️  $1"
}

# Function to check Karabiner DriverKit version
check_karabiner_driver_version() {
    local required_version="6.2.0"
    local driver_version=""
    local version_source=""
    
    # Prioritize Info.plist (more reliable, especially for beta versions)
    # Check the VirtualHIDDevice daemon Info.plist first
    local plist_path=$(find "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice" -name "Info.plist" -path "*/Karabiner-VirtualHIDDevice-Daemon.app/*" 2>/dev/null | head -1)
    if [ -n "$plist_path" ]; then
        driver_version=$(defaults read "$plist_path" CFBundleShortVersionString 2>/dev/null || echo "")
        if [ -n "$driver_version" ]; then
            version_source="Info.plist (VirtualHIDDevice-Daemon)"
        fi
    fi
    
    # Fallback: try any Info.plist in the DriverKit directory
    if [ -z "$driver_version" ]; then
        plist_path=$(find "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice" -name "Info.plist" 2>/dev/null | head -1)
        if [ -n "$plist_path" ]; then
            driver_version=$(defaults read "$plist_path" CFBundleShortVersionString 2>/dev/null || echo "")
            if [ -n "$driver_version" ]; then
                version_source="Info.plist"
            fi
        fi
    fi
    
    # Last resort: try to get version from system extensions (less reliable)
    if [ -z "$driver_version" ] && command -v systemextensionsctl >/dev/null 2>&1; then
        local ext_info=$(systemextensionsctl list | grep -i "Karabiner-DriverKit-VirtualHIDDevice" | head -1)
        if [ -n "$ext_info" ]; then
            # Extract version from output like: (1.8.0/1.8.0) or (6.6.0/6.6.0)
            # Note: systemextensionsctl may show outdated version info
            driver_version=$(echo "$ext_info" | grep -oE '\([0-9]+\.[0-9]+\.[0-9]+/[0-9]+\.[0-9]+\.[0-9]+\)' | head -1 | cut -d'/' -f2 | tr -d ')')
            if [ -n "$driver_version" ]; then
                version_source="systemextensionsctl"
                debug "Warning: systemextensionsctl may show outdated version info"
            fi
        fi
    fi
    
    if [ -z "$driver_version" ]; then
        warning "Could not determine Karabiner DriverKit version"
        warning "Kanata 1.10.0 requires DriverKit v6.2.0 or newer"
        warning "Please update Karabiner Elements to the latest version"
        return 1
    fi
    
    debug "Found Karabiner DriverKit version: $driver_version (from $version_source)"
    
    # If version came from systemextensionsctl and seems too old, double-check Info.plist
    # (systemextensionsctl often shows outdated version info, especially with beta releases)
    if [ "$version_source" = "systemextensionsctl" ]; then
        debug "Version from systemextensionsctl may be outdated, checking Info.plist..."
        local actual_plist=$(find "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice" -name "Info.plist" -path "*/Karabiner-VirtualHIDDevice-Daemon.app/*" 2>/dev/null | head -1)
        if [ -n "$actual_plist" ]; then
            local actual_version=$(defaults read "$actual_plist" CFBundleShortVersionString 2>/dev/null || echo "")
            if [ -n "$actual_version" ] && [ "$actual_version" != "$driver_version" ]; then
                debug "Found newer version in Info.plist: $actual_version (vs $driver_version from systemextensionsctl)"
                driver_version="$actual_version"
                version_source="Info.plist (corrected)"
            fi
        fi
    fi
    
    echo "Found Karabiner DriverKit version: $driver_version"
    
    # Compare versions (simple numeric comparison)
    local required_major=$(echo "$required_version" | cut -d'.' -f1)
    local required_minor=$(echo "$required_version" | cut -d'.' -f2)
    local driver_major=$(echo "$driver_version" | cut -d'.' -f1)
    local driver_minor=$(echo "$driver_version" | cut -d'.' -f2)
    
    if [ "$driver_major" -lt "$required_major" ] || \
       ([ "$driver_major" -eq "$required_major" ] && [ "$driver_minor" -lt "$(echo $required_version | cut -d'.' -f2)" ]); then
        echo "❌ ERROR: Karabiner DriverKit version $driver_version is too old!" >&2
        echo ""
        echo "Kanata 1.10.0 requires Karabiner DriverKit v6.2.0 or newer"
        echo "Your version: $driver_version"
        echo "Required version: $required_version or newer"
        echo ""
        echo "Please update Karabiner Elements:"
        echo "1. Open Karabiner Elements"
        echo "2. Go to the 'Driver' tab"
        echo "3. Click 'Update Driver' if available"
        echo "4. Or download the latest version from: https://karabiner-elements.pqrs.org/"
        return 1
    fi
    
    success "Karabiner DriverKit version is compatible (v$driver_version >= v$required_version)"
    return 0
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
PLIST_PATH="${PLIST_DIR}/com.example.kanata.plist"
LOG_DIR="/Library/Logs/Kanata"
###################################

# 1. Check if Karabiner Elements is installed
debug "Checking for Karabiner Elements"
if [ ! -d "/Applications/Karabiner-Elements.app" ]; then
    error_exit "Karabiner Elements is not installed!"
    echo "Please install Karabiner Elements first from:"
    echo "https://karabiner-elements.pqrs.org/"
    echo
    echo "⚠️  IMPORTANT: Kanata 1.10.0+ requires Karabiner DriverKit v6"
    echo "   Make sure you have the latest version of Karabiner Elements installed"
    echo
    echo "After installation, make sure to:"
    echo "1. Enable all required permissions in System Settings"
    echo "2. Quit Karabiner Elements app AND the menu bar item"
    echo "3. Then run this script again"
    exit 1
fi
success "Karabiner Elements found"

# 1.5. Check Karabiner DriverKit version
debug "Checking Karabiner DriverKit version"
if ! check_karabiner_driver_version; then
    exit 1
fi

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

# 4. Create log directory (system-level, requires sudo)
debug "Creating log directory"
if ! echo "$cli_password" | sudo -S mkdir -p "${LOG_DIR}"; then
    error_exit "Failed to create log directory"
fi
if ! echo "$cli_password" | sudo -S chown root:wheel "${LOG_DIR}"; then
    error_exit "Failed to set ownership for log directory"
fi
success "Log directory created"

# 5. Write Kanata plist file (system-level, requires sudo)
# Note: LaunchDaemon is required because Kanata 1.10.0 needs root access
# to the Virtual HID server socket at /Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server
debug "Creating Kanata plist file"
debug "Config at: ${KANATA_CONFIG}"
debug "Binary at: ${KANATA_BIN}"
debug "Using LaunchDaemon (system-level) - required for Virtual HID server socket access"
if ! echo "$cli_password" | sudo -S tee "${PLIST_PATH}" >/dev/null <<EOF
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
    error_exit "Failed to create Kanata plist file"
fi
success "Kanata plist file created"

# Set ownership and permissions (system-level, requires sudo)
if ! echo "$cli_password" | sudo -S chown root:wheel "${PLIST_PATH}"; then
    error_exit "Failed to set ownership for Kanata plist"
fi
if ! echo "$cli_password" | sudo -S chmod 644 "${PLIST_PATH}"; then
    error_exit "Failed to set permissions for Kanata plist"
fi
success "Kanata plist permissions set"

# 6. Stop existing services (try both old LaunchAgent and LaunchDaemon)
debug "Stopping existing services"
# Try to stop old LaunchAgent (if it exists)
launchctl bootout gui/$(id -u)/com.example.kanata 2>/dev/null || debug "LaunchAgent not running"
# Stop LaunchDaemon
echo "$cli_password" | sudo -S launchctl bootout system "${PLIST_PATH}" 2>/dev/null || debug "LaunchDaemon not running"
success "Existing services stopped"

# 7. Start services
debug "Starting services"

debug "Starting Kanata service (LaunchDaemon - system-level)"
debug "Note: LaunchDaemon is required for Virtual HID server socket access"
debug "launchctl bootstrap system ${PLIST_PATH}"
if ! echo "$cli_password" | sudo -S launchctl bootstrap system "${PLIST_PATH}"; then
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
