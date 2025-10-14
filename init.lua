--- === Kanata ===
---
--- Monitors Kanata keyboard remapper and automatically restarts when new devices are detected
--- Includes optional menu bar controls and script integration
---
--- Download: https://github.com/yourusername/Kanata.spoon
--- @author plasmadice
--- @license MIT

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Kanata"
obj.version = "1.0.1"
obj.author = "plasmadice"
obj.homepage = "https://github.com/plasmadice/Kanata.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- Kanata.logger
--- Variable
--- Logger object used within the Spoon. Can be accessed to set the default log level for the messages coming from the Spoon.
obj.logger = hs.logger.new('Kanata')

--- Kanata.checkInterval
--- Variable
--- Number of seconds between device checks (default: 5)
obj.checkInterval = 5

--- Kanata.kanataConfigPath
--- Variable
--- Path to your Kanata config file (for parsing macos-dev-names-exclude)
--- Set to nil or "" to disable config parsing and monitor all devices
obj.kanataConfigPath = nil

--- Kanata.restartScript
--- Variable
--- Path to your kanata-restart script (required for autostart)
obj.restartScript = nil

--- Kanata.useRaycast
--- Variable
--- Whether to use Raycast script commands for menu integration (default: false)
--- When enabled, adds Raycast deeplinks to menu for kanata-* commands
--- Requires Raycast with script commands configured
obj.useRaycast = false

--- Kanata.showMenuBar
--- Variable
--- Whether to show the menu bar item (default: true)
obj.showMenuBar = true

--- Kanata.startMonitoringOnLoad
--- Variable
--- Whether to start monitoring automatically when the spoon is loaded (default: false)
obj.startMonitoringOnLoad = false

--- Kanata.autoStartKanata
--- Variable
--- Whether to automatically start Kanata service at system boot (default: false)
--- Requires kanataConfigPath and restartScript to be set
--- If enabled but requirements missing, will show alert and open console
obj.autoStartKanata = false

-- Internal state
obj.isMonitoring = false
obj.wasMonitoringBeforeSleep = false
obj.kanataWatcher = nil
obj.excludedDevices = {}
obj.includedDevices = {}
obj.useIncludeList = false
obj.menuBar = nil
obj.configWatcher = nil
obj.configChangeTimer = nil
obj.kanataBinaryPath = nil  -- Stores the actual path to kanata binary

--- Kanata:init()
--- Method
--- Initializes the Spoon
---
--- Returns:
---  * The Kanata object
function obj:init()
  -- Set default config path if not specified
  if not self.kanataConfigPath then
    local defaultPath = os.getenv("HOME") .. "/.config/kanata/kanata.kbd"
    if self:fileExists(defaultPath) then
      self.kanataConfigPath = defaultPath
    end
  end
  
  return self
end

--- Kanata:start()
--- Method
--- Starts the Kanata monitoring service and sets up menu bar
---
--- Returns:
---  * The Kanata object
function obj:start()
  self.logger.i("Starting Kanata Spoon")
  
  -- Enable AppleScript if using Raycast
  if self.useRaycast then
    hs.allowAppleScript(true)
    self.logger.i("AppleScript enabled for Raycast integration")
  end
  
  -- Parse device lists from config
  self:parseDeviceLists(true)
  
  -- Set up config file watcher
  self:setupConfigWatcher()
  
  -- Set up sleep/wake handlers
  self:setupSleepWatcher()
  
  -- Set up URL scheme handlers
  self:setupURLHandlers()
  
  -- Set up menu bar if enabled
  if self.showMenuBar then
    self:setupMenuBar()
  end
  
  -- Handle autostart of Kanata service
  if self.autoStartKanata then
    self:handleAutoStart()
  end
  
  -- Start monitoring if configured to do so
  if self.startMonitoringOnLoad then
    self:startMonitoring()
  end
  
  return self
end

--- Kanata:stop()
--- Method
--- Stops the Kanata monitoring service and cleans up
---
--- Returns:
---  * The Kanata object
function obj:stop()
  self.logger.i("Stopping Kanata Spoon")
  
  -- Stop monitoring
  self:stopMonitoring(true)
  
  -- Clean up watchers
  if self.configWatcher then
    self.configWatcher:stop()
    self.configWatcher = nil
  end
  
  if self.configChangeTimer then
    self.configChangeTimer:stop()
    self.configChangeTimer = nil
  end
  
  -- Remove menu bar
  if self.menuBar then
    self.menuBar:delete()
    self.menuBar = nil
  end
  
  return self
end

--- Kanata:startMonitoring()
--- Method
--- Starts the device monitoring service
---
--- Parameters:
---  * suppressLog - Optional boolean to suppress log messages
---
--- Returns:
---  * The Kanata object
function obj:startMonitoring(suppressLog)
  if self.isMonitoring then
    if not suppressLog then
      self.logger.i("Monitoring service already running")
    end
    self:updateMenuBar()
    return self
  end
  
  if not self:isKanataAvailable() then
    self.logger.e("Cannot start monitoring - Kanata not available")
    hs.alert.show("Cannot start Kanata monitoring!\nKanata is not installed or not in PATH.")
    return self
  end
  
  self.logger.i("Starting Kanata monitoring service")
  self.isMonitoring = true
  
  -- Initialize device list
  local prevDevices = self:getKanataDeviceList()
  
  self.kanataWatcher = hs.timer.doEvery(self.checkInterval, function()
    if not self:isKanataAvailable() then
      self.logger.e("Kanata no longer available, stopping monitoring service")
      self:stopMonitoring()
      hs.alert.show("Kanata monitoring stopped!\nKanata is no longer available.")
      return
    end
    
    local currDevices = self:getKanataDeviceList()
    local newDevices, removedDevices = self:getDeviceChanges(prevDevices, currDevices)

    -- Log removed devices
    if #removedDevices > 0 then
      local removedList = table.concat(removedDevices, ", ")
      self.logger.i("Device(s) removed: " .. removedList)
    end

    -- Restart if new devices detected
    if #newDevices > 0 then
      self:restartKanata(newDevices, true)
    end

    prevDevices = currDevices
  end)
  
  self:updateMenuBar()
  hs.alert.show("Kanata monitoring started")
  
  return self
end

--- Kanata:stopMonitoring()
--- Method
--- Stops the device monitoring service
---
--- Parameters:
---  * suppressAlert - Optional boolean to suppress alert notifications
---
--- Returns:
---  * The Kanata object
function obj:stopMonitoring(suppressAlert)
  if not self.isMonitoring then
    if not suppressAlert then
      self.logger.i("Monitoring service not running")
    end
    return self
  end
  
  self.logger.i("Stopping Kanata monitoring service")
  self.isMonitoring = false
  
  if self.kanataWatcher then
    self.kanataWatcher:stop()
    self.kanataWatcher = nil
  end
  
  self:updateMenuBar()
  
  if not suppressAlert then
    hs.alert.show("Kanata monitoring stopped")
  end
  
  return self
end

--- Kanata:toggleMonitoring()
--- Method
--- Toggles the monitoring service on/off
---
--- Returns:
---  * The Kanata object
function obj:toggleMonitoring()
  if self.isMonitoring then
    self:stopMonitoring()
  else
    self:startMonitoring()
  end
  return self
end

-- Internal Methods

function obj:isKanataAvailable()
  -- If we already found the binary, just verify it still exists
  if self.kanataBinaryPath and self:fileExists(self.kanataBinaryPath) then
    return true
  end
  
  -- First try PATH
  local result = hs.execute("which kanata 2>/dev/null")
  if result and result ~= "" then
    self.kanataBinaryPath = result:gsub("%s+$", "")  -- Trim whitespace
    self.logger.i("Found Kanata in PATH: " .. self.kanataBinaryPath)
    return true
  end
  
  -- Check common installation locations
  local commonPaths = {
    "/opt/homebrew/bin/kanata",  -- Homebrew (Apple Silicon)
    "/usr/local/bin/kanata",      -- Homebrew (Intel)
    os.getenv("HOME") .. "/.cargo/bin/kanata",  -- Cargo/Rust
    "/opt/kanata/kanata",         -- Custom install
  }
  
  for _, path in ipairs(commonPaths) do
    if self:fileExists(path) then
      self.kanataBinaryPath = path
      self.logger.i("Found Kanata at: " .. path)
      return true
    end
  end
  
  self.kanataBinaryPath = nil
  return false
end

function obj:getKanataCommand()
  -- Ensure we have found kanata
  if not self:isKanataAvailable() then
    return nil
  end
  
  -- Return the full path or just "kanata" if in PATH
  return self.kanataBinaryPath or "kanata"
end

function obj:isKanataServiceRunning()
  -- Check if Kanata process is running with port 10000
  -- Note: lsof -i:10000 doesn't work for root processes without sudo,
  -- so we check the process list instead
  local psOutput = hs.execute("ps aux | grep -E '[k]anata.*--port.*10000'")
  return psOutput and psOutput ~= ""
end

function obj:startKanataService()
  if not self.restartScript then
    self.logger.e("Cannot start Kanata: restartScript not configured")
    return false
  end
  
  if not self:fileExists(self.restartScript) then
    self.logger.e("Cannot start Kanata: Restart script not found at " .. self.restartScript)
    return false
  end
  
  self.logger.i("Starting Kanata service via script: " .. self.restartScript)
  
  -- Run restart script
  local task = hs.task.new(self.restartScript, function(exitCode, stdOut, stdErr)
    if exitCode == 0 then
      self.logger.i("Kanata service started successfully")
    else
      self.logger.e("Failed to start Kanata service (exit code: " .. tostring(exitCode) .. ")")
      if stdErr and stdErr ~= "" then
        self.logger.e("Error output: " .. stdErr)
      end
    end
  end, {})
  
  local success = task:start()
  if not success then
    self.logger.e("Failed to execute restart script")
    return false
  end
  
  return true
end

function obj:handleAutoStart()
  self.logger.i("Checking autostart configuration...")
  
  -- Validate requirements
  local missingRequirements = {}
  
  if not self.kanataConfigPath or self.kanataConfigPath == "" then
    table.insert(missingRequirements, "kanataConfigPath not set")
  elseif not self:fileExists(self.kanataConfigPath) then
    table.insert(missingRequirements, "kanataConfigPath file not found: " .. self.kanataConfigPath)
  end
  
  -- Check for restart script
  if not self.restartScript then
    table.insert(missingRequirements, "restartScript not configured")
  elseif not self:fileExists(self.restartScript) then
    table.insert(missingRequirements, "restartScript not found: " .. self.restartScript)
  end
  
  -- Check if Kanata binary is available
  if not self:isKanataAvailable() then
    table.insert(missingRequirements, "Kanata binary not found in PATH")
  end
  
  -- If requirements are missing, show alert and open console
  if #missingRequirements > 0 then
    local errorMsg = "Kanata autostart enabled but requirements missing:\n" .. table.concat(missingRequirements, "\n")
    self.logger.e(errorMsg)
    
    -- Show alert
    hs.alert.show("⚠️ Kanata Autostart Failed\nCheck Console for details", 5)
    
    -- Open Hammerspoon console
    hs.openConsole()
    
    return
  end
  
  -- All requirements met, check if Kanata is already running
  if self:isKanataServiceRunning() then
    self.logger.i("Kanata service is already running, skipping autostart")
    return
  end
  
  -- Start Kanata service
  self.logger.i("Kanata service not running, starting via autostart...")
  local success = self:startKanataService()
  
  if success then
    self.logger.i("Kanata autostart initiated successfully")
    hs.alert.show("✅ Kanata started automatically", 2)
  else
    self.logger.e("Kanata autostart failed")
    hs.alert.show("❌ Kanata autostart failed\nCheck Console for details", 5)
    hs.openConsole()
  end
end

function obj:getKanataDeviceList()
  local kanataCmd = self:getKanataCommand()
  if not kanataCmd then
    return {}
  end
  
  local output = hs.execute(kanataCmd .. " -l 2>/dev/null")
  if not output then
    return {}
  end
  
  local devices = {}
  for line in output:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")  -- trim whitespace
    if line ~= "" then
      devices[line] = true
    end
  end
  return devices
end

function obj:parseDeviceLists(logDevices)
  local excluded = {}
  local included = {}
  
  -- Check if config path is set
  if not self.kanataConfigPath or self.kanataConfigPath == "" then
    self.excludedDevices = excluded
    self.includedDevices = included
    self.useIncludeList = false
    return
  end
  
  -- Check if config file exists
  local file = io.open(self.kanataConfigPath, "r")
  if not file then
    if logDevices then
      self.logger.w("Could not open Kanata config file at: " .. self.kanataConfigPath)
    end
    self.excludedDevices = excluded
    self.includedDevices = included
    self.useIncludeList = false
    return
  end
  
  local content = file:read("*all")
  file:close()
  
  -- Look for macos-dev-names-include and macos-dev-names-exclude sections
  local inIncludeSection = false
  local inExcludeSection = false
  
  for line in content:gmatch("[^\r\n]+") do
    -- Trim whitespace
    line = line:match("^%s*(.-)%s*$")
    
    -- Check if we're entering the include section
    if line:match("macos%-dev%-names%-include%s*%(") then
      inIncludeSection = true
      inExcludeSection = false
    -- Check if we're entering the exclude section
    elseif line:match("macos%-dev%-names%-exclude%s*%(") then
      inExcludeSection = true
      inIncludeSection = false
    -- Check if we're exiting a section
    elseif (inIncludeSection or inExcludeSection) and line:match("^%)") then
      inIncludeSection = false
      inExcludeSection = false
    -- Extract device names
    elseif inIncludeSection then
      local deviceName = line:match('"([^"]+)"')
      if deviceName then
        table.insert(included, deviceName)
        if logDevices then
          self.logger.i("Including device for monitoring: " .. deviceName)
        end
      end
    elseif inExcludeSection then
      local deviceName = line:match('"([^"]+)"')
      if deviceName then
        table.insert(excluded, deviceName)
        if logDevices then
          self.logger.i("Excluding device from monitoring: " .. deviceName)
        end
      end
    end
  end
  
  self.excludedDevices = excluded
  self.includedDevices = included
  self.useIncludeList = #included > 0
  
  if logDevices then
    if self.useIncludeList then
      self.logger.i("Device monitoring mode: INCLUDE list (only monitor listed devices)")
    elseif #excluded > 0 then
      self.logger.i("Device monitoring mode: EXCLUDE list (monitor all except listed)")
    else
      self.logger.i("Device monitoring mode: ALL devices (no include/exclude list)")
    end
  end
end

function obj:shouldMonitorDevice(deviceName)
  -- If include list exists, only monitor devices in the include list
  if self.useIncludeList then
    for _, included in ipairs(self.includedDevices) do
      if deviceName == included then
        return true
      end
    end
    return false
  end
  
  -- Otherwise, monitor all devices except those in exclude list
  for _, excluded in ipairs(self.excludedDevices) do
    if deviceName == excluded then
      return false
    end
  end
  
  return true
end

function obj:getDeviceChanges(prev, curr)
  local added = {}
  local removed = {}
  
  -- Find added devices (only devices we should monitor)
  for name, _ in pairs(curr) do
    if not prev[name] and self:shouldMonitorDevice(name) then
      table.insert(added, name)
    end
  end
  
  -- Find removed devices (only devices we should monitor)
  for name, _ in pairs(prev) do
    if not curr[name] and self:shouldMonitorDevice(name) then
      table.insert(removed, name)
    end
  end
  
  return added, removed
end

function obj:restartKanata(newDevices, suppressLog)
  if not self:isKanataAvailable() then
    self.logger.e("Kanata not available, stopping monitoring service")
    self:stopMonitoring()
    hs.alert.show("Kanata not available!\nStopping monitoring service.")
    return
  end
  
  local deviceList = table.concat(newDevices, ", ")
  self.logger.i("New device(s) detected: " .. deviceList .. " - Restarting Kanata")
  
  -- Determine which restart script to use
  local scriptPath = self.restartScript
  if not scriptPath and self.scriptsPath then
    scriptPath = self.scriptsPath .. "/kanata-restart.sh"
    if not self:fileExists(scriptPath) then
      scriptPath = nil
    end
  end
  
  if not scriptPath then
    self.logger.w("No restart script configured or found")
    return
  end
  
  -- Run restart script with quiet flag to suppress "Service already running" messages
  local args = {}
  if suppressLog then
    table.insert(args, "--quiet")
  end
  
  local task = hs.task.new(scriptPath, function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then
      self.logger.e("Restart script failed with exit code " .. tostring(exitCode))
    end
  end, args)
  task:start()
end

function obj:setupConfigWatcher()
  if not self.kanataConfigPath or self.kanataConfigPath == "" then
    return
  end
  
  local kanataConfigDir = self.kanataConfigPath:match("(.*/)")
  local kanataConfigFilename = self.kanataConfigPath:match("([^/]+)$")
  
  if not kanataConfigDir or not kanataConfigFilename then
    return
  end
  
  self.configWatcher = hs.pathwatcher.new(kanataConfigDir, function(files)
    for _, file in ipairs(files) do
      -- Check if the changed file matches our config file
      if file == self.kanataConfigPath or file:match(kanataConfigFilename .. "$") then
        -- Cancel existing timer if it exists
        if self.configChangeTimer then
          self.configChangeTimer:stop()
        end
        
        -- Set new timer to process after 500ms of no changes (debounce)
        self.configChangeTimer = hs.timer.doAfter(0.5, function()
          -- Only process if monitoring is enabled
          if self.isMonitoring then
            self.logger.i("Kanata config file changed - validating configuration")
            hs.alert.show("Validating Kanata configuration...")
            
            -- Reload device lists first
            self:parseDeviceLists(false)
            
            -- Validate the config with --check
            local kanataCmd = self:getKanataCommand()
            if not kanataCmd then
              self.logger.e("Kanata command not available")
              hs.alert.show("Kanata not available!")
              return
            end
            
            local checkCmd = kanataCmd .. " -c " .. self.kanataConfigPath .. " --nodelay --check 2>&1"
            local checkOutput, checkStatus = hs.execute(checkCmd)
            
            if checkStatus then
              -- Config is valid, proceed with restart
              self.logger.i("Config validation passed - restarting Kanata")
              hs.alert.show("Success! Restarting Kanata")
              self:restartKanata({}, true)
            else
              -- Config has errors, show them to user
              self.logger.e("Config validation failed:")
              self.logger.e(checkOutput)
              
              -- Show error alert with first line of error
              local firstLine = checkOutput:match("^(.-)\n") or checkOutput
              hs.alert.show("Kanata config error!\n" .. firstLine:sub(1, 100))
              
              -- Show detailed notification
              hs.notify.new({
                title = "Kanata Config Error",
                informativeText = checkOutput:sub(1, 500),
                soundName = "Basso"
              }):send()
            end
          else
            -- Monitoring is disabled, just log the change
            self.logger.i("Kanata config file changed (monitoring disabled - no action taken)")
          end
          
          self.configChangeTimer = nil
        end)
        break
      end
    end
  end)
  
  self.configWatcher:start()
  self.logger.i("Watching Kanata config file: " .. self.kanataConfigPath)
end

function obj:setupSleepWatcher()
  self.sleepWatcher = hs.caffeinate.watcher.new(function(eventType)
    if eventType == hs.caffeinate.watcher.systemDidSleep then
      if self.isMonitoring then
        self.logger.i("Device going to sleep - stopping monitoring service")
        self.wasMonitoringBeforeSleep = true
        self:stopMonitoring(true)
      end
    elseif eventType == hs.caffeinate.watcher.systemDidWake then
      if self.wasMonitoringBeforeSleep then
        self.logger.i("Device woke up - restarting monitoring service")
        self.wasMonitoringBeforeSleep = false
        self:startMonitoring(true)
      end
    end
  end)
  
  self.sleepWatcher:start()
end

function obj:setupURLHandlers()
  hs.urlevent.bind("kanata", function(eventName, params)
    local action = params["action"]
    local suppressLog = params["suppressLog"] == "true"
    if action == "start" then
      self:startMonitoring(suppressLog)
    elseif action == "stop" then
      self:stopMonitoring()
    elseif action == "toggle" then
      self:toggleMonitoring()
    else
      self.logger.e("Unknown action: " .. tostring(action))
    end
  end)
end

function obj:setupMenuBar()
  self.menuBar = hs.menubar.new()
  self:updateMenuBar()
end

function obj:updateMenuBar()
  if not self.menuBar then
    return
  end
  
  -- Update icon based on monitoring and service status
  local kanataRunning = self:isKanataServiceRunning()
  
  if self.isMonitoring and kanataRunning then
    -- Both monitoring and Kanata service are running
    self.menuBar:setTitle("⌨️")
    self.menuBar:setTooltip("Kanata monitoring: Active")
  elseif self.isMonitoring and not kanataRunning then
    -- Monitoring is running but Kanata service is not
    self.menuBar:setTitle("🔎")
    self.menuBar:setTooltip("Kanata monitoring: Watching (service not running)")
  else
    -- Monitoring is not running
    self.menuBar:setTitle("😵️")
    self.menuBar:setTooltip("Kanata monitoring: Inactive")
  end
  
  -- Build menu
  local menu = {}
  
  -- Combined service control (Kanata + Monitoring)
  local bothRunning = kanataRunning and self.isMonitoring
  
  if bothRunning then
    table.insert(menu, {
      title = "Stop Service",
      fn = function() self:stopService() end
    })
  else
    table.insert(menu, {
      title = "Start Service",
      fn = function() self:startService() end
    })
  end
  
  -- Monitoring-only controls
  if self.isMonitoring then
    table.insert(menu, {
      title = "Monitoring Inputs...",
      fn = function() self:stopMonitoring() end
    })
  else
    table.insert(menu, {
      title = "Start Monitoring",
      fn = function() self:startMonitoring() end
    })
  end
  
  -- Add Raycast commands if enabled
  if self.useRaycast then
    table.insert(menu, { title = "-" }) -- Separator
    
    -- Add Raycast command menu items
    table.insert(menu, {
      title = "Restart Kanata",
      fn = function() self:openRaycastCommand("kanata-restart") end
    })
    table.insert(menu, {
      title = "Stop Kanata",
      fn = function() self:openRaycastCommand("kanata-stop") end
    })
    table.insert(menu, {
      title = "Cleanup Kanata",
      fn = function() self:openRaycastCommand("kanata-cleanup") end
    })
    table.insert(menu, {
      title = "Install Kanata",
      fn = function() self:openRaycastCommand("kanata-install") end
    })
  end
  
  -- Configuration options
  table.insert(menu, { title = "-" })
  
  -- Open Kanata config if path is set
  if self.kanataConfigPath and self.kanataConfigPath ~= "" then
    table.insert(menu, {
      title = "Open Kanata Config",
      fn = function() self:openFile(self.kanataConfigPath) end
    })
  end
  
  -- Open Hammerspoon config
  table.insert(menu, {
    title = "Open Hammerspoon Config",
    fn = function()
      local configPath = hs.configdir .. "/init.lua"
      self:openFile(configPath)
    end
  })
  
  -- Utility options
  table.insert(menu, { title = "-" })
  table.insert(menu, {
    title = "Hammerspoon Preferences",
    fn = function() hs.openPreferences() end
  })
  table.insert(menu, {
    title = "Show Console",
    fn = function() hs.openConsole() end
  })
  table.insert(menu, {
    title = "Quit Hammerspoon",
    fn = function() self:quitHammerspoon() end
  })
  
  -- Info section
  table.insert(menu, { title = "-" })
  table.insert(menu, {
    title = "Kanata.spoon v" .. self.version,
    disabled = true
  })
  
  self.menuBar:setMenu(menu)
end

function obj:openRaycastCommand(commandName)
  local deeplink = "raycast://script-commands/" .. commandName
  self.logger.i("Opening Raycast command: " .. deeplink)
  
  local result = hs.execute(string.format('open "%s"', deeplink))
  if not result then
    self.logger.w("Failed to open Raycast deeplink (is Raycast installed?)")
  end
end

function obj:startService()
  self.logger.i("Starting Kanata service and monitoring")
  
  -- Start Kanata if not running
  if not self:isKanataServiceRunning() then
    local success = self:startKanataService()
    if not success then
      hs.alert.show("Failed to start Kanata service")
      return
    end
    -- Give Kanata time to start
    hs.timer.usleep(1500000) -- 1.5 seconds
  end
  
  -- Start monitoring if not running
  if not self.isMonitoring then
    self:startMonitoring(true) -- Suppress the "monitoring started" alert
  end
  
  -- Update menu to reflect new state
  self:updateMenuBar()
  
  hs.alert.show("✅ Service started")
end

function obj:stopService()
  self.logger.i("Stopping Kanata service and monitoring")
  
  -- Stop monitoring first
  if self.isMonitoring then
    self:stopMonitoring(true) -- Suppress alert
  end
  
  -- Stop Kanata service using Raycast kanata-stop command
  if self:isKanataServiceRunning() then
    if self.useRaycast then
      self.logger.i("Stopping Kanata via Raycast command")
      self:openRaycastCommand("kanata-stop")
    else
      -- Fallback to local script if Raycast not enabled
      local spoonPath = hs.spoons.scriptPath() .. "/" .. self.name .. ".spoon"
      local stopScript = spoonPath .. "/scripts/kanata-stop.sh"
      
      if self:fileExists(stopScript) then
        self.logger.i("Stopping Kanata via local script")
        hs.execute(string.format('bash "%s" &', stopScript))
      else
        self.logger.w("Stop script not found, Kanata may remain running")
      end
    end
    hs.timer.usleep(500000) -- 500ms
  end
  
  -- Update menu to reflect new state
  self:updateMenuBar()
  
  hs.alert.show("✅ Service stopped")
end

function obj:openFile(filePath)
  if not filePath or filePath == "" then
    self.logger.w("No file path provided")
    hs.alert.show("No file path configured")
    return
  end
  
  self.logger.d("openFile called with: " .. filePath)
  
  -- Expand ~ to home directory if present
  if filePath:sub(1, 1) == "~" then
    filePath = os.getenv("HOME") .. filePath:sub(2)
    self.logger.d("After ~ expansion: " .. filePath)
  end
  
  -- If path is relative, make it relative to config directory
  if filePath:sub(1, 1) ~= "/" then
    filePath = hs.configdir .. "/" .. filePath
    self.logger.d("After relative path resolution: " .. filePath)
  end
  
  if not self:fileExists(filePath) then
    self.logger.e("File not found: " .. filePath)
    hs.alert.show("File not found:\n" .. filePath)
    return
  end
  
  self.logger.i("Opening file: " .. filePath)
  
  -- Use hs.open() instead of hs.execute() for better reliability
  local success = hs.open(filePath)
  if not success then
    self.logger.e("Failed to open file: " .. filePath)
    hs.alert.show("Failed to open file:\n" .. filePath)
  end
end

function obj:quitHammerspoon()
  self.logger.i("Quit Hammerspoon requested")
  
  -- Stop monitoring service first
  if self.isMonitoring then
    self:stopMonitoring(true) -- Suppress alert
  end
  
  -- Stop Kanata service if it's running
  if self:isKanataServiceRunning() then
    if self.useRaycast then
      self.logger.i("Stopping Kanata via Raycast command")
      self:openRaycastCommand("kanata-stop")
    else
      -- Fallback to local script
      local spoonPath = hs.spoons.scriptPath() .. "/" .. self.name .. ".spoon"
      local stopScript = spoonPath .. "/scripts/kanata-stop.sh"
      
      if self:fileExists(stopScript) then
        self.logger.i("Stopping Kanata via local script")
        hs.execute(string.format('bash "%s" &', stopScript))
      else
        self.logger.w("Stop script not found, Kanata may remain running")
      end
    end
    -- Give it a moment to start stopping
    hs.timer.usleep(500000) -- 500ms
  end
  
  -- Now quit Hammerspoon
  self.logger.i("Quitting Hammerspoon...")
  hs.osascript.applescript('tell application "Hammerspoon" to quit')
end

-- Utility functions

function obj:fileExists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

function obj:directoryExists(path)
  local result = hs.execute("test -d '" .. path .. "' && echo 'true' || echo 'false'")
  return result and result:match("true") ~= nil
end

return obj

