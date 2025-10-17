-- Example configuration for Kanata.spoon
-- Copy this file to your ~/.hammerspoon/init.lua and customize as needed

-- Load the Kanata Spoon
hs.loadSpoon("Kanata")

--[[
====================================
LOGGING CONFIGURATION
====================================
--]]

-- Set logger level (options: 'debug', 'info', 'warn', 'error', 'nothing')
-- 'debug' shows all messages including device detection details
-- 'info' shows important events (device changes, restarts)
-- 'warn' shows warnings and errors only
-- 'error' shows errors only
-- 'nothing' disables all logging
spoon.Kanata.logger.setLogLevel('info')

--[[
====================================
CORE CONFIGURATION
====================================
--]]

-- Path to Kanata config file (optional, enables device filtering)
-- If set, spoon will parse macos-dev-names-include and macos-dev-names-exclude sections
-- If nil or empty string, all devices will be monitored
-- Default: nil (no filtering)
spoon.Kanata.kanataConfigPath = os.getenv("HOME") .. "/.config/kanata/kanata.kbd"

-- Path to restart script (required for autostart functionality)
-- This script should start/restart the Kanata service
-- Can be relative to Hammerspoon config dir or absolute path
-- Default: nil (autostart disabled)
spoon.Kanata.restartScript = "Spoons/Kanata.spoon/scripts/kanata-restart.sh"

--[[
====================================
MONITORING CONFIGURATION
====================================
--]]

-- Check interval in seconds (default: 5)
-- How often to check for new/removed devices
-- Lower values = more responsive but higher CPU usage
-- Higher values = less responsive but lower CPU usage
-- Range: 1-60 seconds recommended
spoon.Kanata.checkInterval = 5

-- Port for health check API (optional)
-- If set, uses JSON API to verify Kanata is running and healthy
-- Example: kanata -p 10000 (then set this to 10000)
-- If nil, falls back to process-based detection
-- Benefits: More reliable, verifies Kanata is actually responding
-- Default: nil (process-based detection)
spoon.Kanata.port = nil

--[[
====================================
UI CONFIGURATION
====================================
--]]

-- Show menu bar icon (default: true)
-- If true, shows ⌨️ icon in menu bar with controls
-- If false, spoon runs in background without menu
-- Menu provides: Start/Stop Service, Raycast commands, config access
spoon.Kanata.showMenuBar = true

--[[
====================================
AUTO-START CONFIGURATION
====================================
--]]

-- Start monitoring automatically when spoon loads (default: false)
-- If true, monitoring starts immediately after spoon initialization
-- If false, you must manually start monitoring via menu or URL scheme
-- Note: This only starts monitoring, not the Kanata service
spoon.Kanata.startMonitoringOnLoad = false

-- Auto-start Kanata service at system boot (default: false)
-- Requires both kanataConfigPath and restartScript to be set
-- If enabled but requirements missing, shows alert and opens console
-- Note: This only starts the service, not monitoring (use startMonitoringOnLoad for that)
-- Recommended: Set to true if you want Kanata to start automatically
spoon.Kanata.autoStartKanata = false

--[[
====================================
RAYCAST INTEGRATION (OPTIONAL)
====================================
--]]

-- Enable Raycast integration (default: false)
-- If true, adds Raycast command menu items and enables AppleScript
-- Setup required:
-- 1. Install Raycast from https://www.raycast.com/
-- 2. Add ~/.hammerspoon/Spoons/Kanata.spoon/scripts/ to Raycast Script Commands
-- 3. Approve scripts on first use (macOS will prompt)
-- See RAYCAST.md for detailed setup instructions
-- Commands added: Restart Kanata, Stop Kanata, Cleanup Kanata, Install Kanata
spoon.Kanata.useRaycast = false

--[[
====================================
START THE SPOON
====================================
--]]

-- Start the Kanata Spoon with the above configuration
spoon.Kanata:start()

--[[
====================================
USAGE NOTES
====================================

Menu Bar Controls:
- Start/Stop Service: Controls both Kanata service and monitoring
- Raycast commands (if enabled): Restart, Stop, Cleanup, Install
- Config access: Open Kanata/Hammerspoon configs
- Utility: Preferences, Console, Quit

URL Scheme:
- Start monitoring: open "hammerspoon://kanata?action=start"
- Stop monitoring: open "hammerspoon://kanata?action=stop"
- Toggle monitoring: open "hammerspoon://kanata?action=toggle"

Features:
- Automatic device detection and Kanata restart
- Config file validation on changes
- Sleep/wake handling
- Optional Raycast integration
- Auto-start at boot
- Health check API support
- Device filtering via config

Configuration Tips:
- For development: Set logger to 'debug' to see all activity
- For production: Set logger to 'info' or 'warn' for cleaner logs
- For headless use: Set showMenuBar to false
- For automatic startup: Set both autoStartKanata and startMonitoringOnLoad to true
- For device filtering: Set kanataConfigPath and configure include/exclude lists

Documentation:
- README.md - Complete documentation
- RAYCAST.md - Raycast setup
- CHANGELOG.md - Version history

--]]

-- Add your other Hammerspoon configurations below this line