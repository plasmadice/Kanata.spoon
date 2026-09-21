-- Example configuration for Kanata.spoon (v1.1.0)
-- Copy relevant parts into your ~/.hammerspoon/init.lua

--[[
====================================
PREREQUISITES (one-time setup)
====================================

1. Install Kanata and the bundled standalone VirtualHID DriverKit:
   bash ~/.hammerspoon/Spoons/Kanata.spoon/scripts/kanata-install.sh

2. Grant permissions in System Settings → Privacy & Security:
   - Input Monitoring → kanata
   - Accessibility → kanata (if required)

3. Copy Kanata.spoon to ~/.hammerspoon/Spoons/
   Then add the configuration below to your init.lua.
--]]

--[[
====================================
MINIMAL SETUP
====================================
The spoon auto-discovers the idempotent kanata-install.sh management script and
auto-detects your kanata config at ~/.config/kanata/kanata.kbd.
--]]

hs.loadSpoon("Kanata")
spoon.Kanata.startMonitoringOnLoad = true  -- Watch for new keyboards and restart kanata automatically
spoon.Kanata:start()

--[[
====================================
FULL CONFIGURATION (all options)
====================================
--]]

hs.loadSpoon("Kanata")

-- Logging ('debug', 'info', 'warn', 'error', 'nothing')
spoon.Kanata.logger.setLogLevel('info')

--[[  CORE  ]]

-- Path to Kanata config file (optional — auto-detected at ~/.config/kanata/kanata.kbd)
-- Only needed if your config is in a non-standard location.
-- When set, the spoon parses macos-dev-names-include / macos-dev-names-exclude for smart
-- device filtering and validates the config before reloading.
spoon.Kanata.kanataConfigPath = os.getenv("HOME") .. "/.config/kanata/kanata.kbd"

-- Shared install/restart script (auto-discovered from scripts/ if not set)
-- Override only if you keep the script somewhere else.
-- spoon.Kanata.restartScript = hs.configdir .. "/Spoons/Kanata.spoon/scripts/kanata-install.sh"

--[[  MONITORING  ]]

-- How often to poll kanata --list for device changes (seconds, default: 5)
spoon.Kanata.checkInterval = 5

-- Port for health-check API (optional, enables JSON API health check instead of process scan)
-- Start kanata with: kanata -c kanata.kbd --port 10000
-- spoon.Kanata.port = 10000

--[[  UI  ]]

spoon.Kanata.showMenuBar = true  -- ⌨️ icon in menu bar

--[[  AUTO-START  ]]

-- Start device monitoring automatically when the spoon loads
spoon.Kanata.startMonitoringOnLoad = true

--[[  START  ]]

spoon.Kanata:start()

--[[
====================================
URL SCHEME
====================================
open "hammerspoon://kanata?action=start"   -- start monitoring
open "hammerspoon://kanata?action=stop"    -- stop monitoring
open "hammerspoon://kanata?action=toggle"  -- toggle monitoring
--]]

-- Add your other Hammerspoon configurations below this line
