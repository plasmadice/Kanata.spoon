-- Example configuration for Kanata.spoon
-- Copy this file to your ~/.hammerspoon/init.lua and customize as needed

-- Load the Kanata Spoon
hs.loadSpoon("Kanata")

--[[
====================================
BASIC CONFIGURATION
====================================
--]]

-- Path to Kanata config (optional, enables device filtering)
spoon.Kanata.kanataConfigPath = os.getenv("HOME") .. "/.config/kanata/kanata.kbd"

-- Path to restart script (required for autostart)
spoon.Kanata.restartScript = "Spoons/Kanata.spoon/scripts/kanata-restart.sh"

-- Optional settings
spoon.Kanata.checkInterval = 5  -- Seconds between device checks
spoon.Kanata.showMenuBar = true  -- Show menu bar icon
spoon.Kanata.startMonitoringOnLoad = false  -- Auto-start monitoring
spoon.Kanata.autoStartKanata = false  -- Auto-start Kanata at boot

--[[
====================================
RAYCAST INTEGRATION (OPTIONAL)
====================================
--]]

-- Enable Raycast integration (default: false)
-- Setup: Add scripts folder to Raycast Script Commands, then enable
-- See RAYCAST.md for setup instructions
-- Note: Automatically enables AppleScript and scripts need approval on first use
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
- Start/Stop Monitor: Controls monitoring only
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

Documentation:
- README.md - Complete documentation
- RAYCAST.md - Raycast setup
- CHANGELOG.md - Version history

--]]

-- Add your other Hammerspoon configurations below this line
