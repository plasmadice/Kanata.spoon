--- === Kanata ===
---
--- Monitors Kanata keyboard remapper and automatically restarts when new devices are detected.
--- Kanata is managed as a Homebrew service (sudo brew services start kanata).
--- Includes optional menu bar controls.
---
--- Download: https://github.com/plasmadice/Kanata.spoon
--- @author plasmadice
--- @license MIT

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Kanata"
obj.version = "1.11.2"
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
--- Path to the idempotent Kanata install/restart script (auto-discovered from
--- the spoon's scripts/ folder if not set).
obj.restartScript = nil

--- Kanata.showMenuBar
--- Variable
--- Whether to show the menu bar item (default: true)
obj.showMenuBar = true

--- Kanata.startMonitoringOnLoad
--- Variable
--- Whether to start monitoring automatically when the spoon is loaded (default: false)
obj.startMonitoringOnLoad = false

--- Kanata.port
--- Variable
--- Port number for Kanata health check API (optional)
--- When provided, enables health check via JSON API to determine if Kanata is running and healthy
--- If not set or nil, falls back to process-based detection
obj.port = nil

--- Kanata.reloadOnConfigChange
--- Variable
--- Whether to automatically validate and restart Kanata when kanata.kbd is saved (default: false)
--- When false, config file changes are ignored (device lists are still parsed on spoon load)
--- When true, requires monitoring to be active and kanataConfigPath to be set
obj.reloadOnConfigChange = false

--- Kanata.restartCooldown
--- Variable
--- Seconds to block further auto-restarts after one has been triggered (default: 15)
--- Prevents a restart loop: when kanata restarts it briefly disconnects, which can make
--- the device-check poll see "new" devices and fire another restart immediately.
obj.restartCooldown = 15

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
obj.kanataBinaryPath = nil
obj.operationProgress = nil
obj.operationStatus = nil
obj.operationGeneration = 0
obj.activeManagementTask = nil
obj.ignoreDeviceChangesUntil = 0
obj.serviceStateSettingKey = "Kanata.serviceDesiredRunning"
obj.shutdownCallbackInstalled = false
obj.recentlyRemovedDevices = {}
obj.spoonPath = nil  -- Absolute path to the spoon directory, set in init()
obj.lastRestartTime = 0

--- Kanata:init()
--- Method
--- Initializes the Spoon
---
--- Returns:
---  * The Kanata object
function obj:init()
  -- Resolve the spoon's own directory so scripts can be found relative to it
  self.spoonPath = hs.configdir .. "/Spoons/" .. self.name .. ".spoon"

  -- Install and restart deliberately use the same idempotent script.
  if not self.restartScript then
    local candidate = self.spoonPath .. "/scripts/kanata-install.sh"
    if self:fileExists(candidate) then
      self.restartScript = candidate
      self.logger.i("Auto-discovered restart script: " .. candidate)
    end
  end

  -- Auto-discover kanata config path if not set
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
  self.logger.i("Kanata Spoon version: " .. self.version)
  self.logger.i("Check interval: " .. self.checkInterval .. " seconds")
  self.logger.i("Config path: " .. (self.kanataConfigPath or "not set"))
  self.logger.i("Restart script: " .. (self.restartScript or "not set"))
  self.logger.i("Port for health check: " .. (self.port or "not set"))
  
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

  self:installShutdownCallback()
  
  -- Restore the user's last explicit Start/Stop choice. A missing setting
  -- defaults to running so existing installations retain autostart behavior.
  if not self:isServiceDesiredRunning() then
    self.logger.i("Kanata service was explicitly stopped; preserving stopped state")
    return self
  end

  -- Service health is checked when startup is desired. Monitoring waits for
  -- that asynchronous start/repair operation to finish successfully.
  self:handleAutoStart(function(exitCode)
    if exitCode ~= 0 then
      return
    end

    if self.startMonitoringOnLoad then
      self.logger.i("Auto-starting monitoring service...")
      self:startMonitoring()
    else
      self.logger.i("Monitoring not auto-started (startMonitoringOnLoad = false)")
    end
  end)
  
  return self
end

function obj:isServiceDesiredRunning()
  local desired = hs.settings.get(self.serviceStateSettingKey)
  if desired == nil then
    return true
  end
  return desired == true
end

function obj:setServiceDesiredRunning(desired)
  hs.settings.set(self.serviceStateSettingKey, desired == true)
  self.logger.i("Persisted Kanata service state: " .. (desired and "running" or "stopped"))
end

function obj:installShutdownCallback()
  if self.shutdownCallbackInstalled then
    return
  end

  local previousShutdownCallback = hs.shutdownCallback
  hs.shutdownCallback = function()
    if previousShutdownCallback then
      local ok, err = pcall(previousShutdownCallback)
      if not ok then
        self.logger.e("Previous Hammerspoon shutdown callback failed: " .. tostring(err))
      end
    end

    if self:isKanataServiceRunningProcessBased() and self.restartScript then
      self.logger.i("Hammerspoon is shutting down; safely stopping Kanata")
      local command = string.format("%q --stop", self.restartScript)
      local output, status = hs.execute(command)
      if not status then
        self.logger.e("Safe Kanata shutdown failed: " .. tostring(output))
      end
    end
  end
  self.shutdownCallbackInstalled = true
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
  self.logger.i("Initial device list: " .. self:getDeviceListString(prevDevices))
  
  self.kanataWatcher = hs.timer.doEvery(self.checkInterval, function()
    self.logger.d("Checking for device changes...")
    
    if not self:isKanataAvailable() then
      self.logger.e("Kanata no longer available, stopping monitoring service")
      self:stopMonitoring()
      hs.alert.show("Kanata monitoring stopped!\nKanata is no longer available.")
      return
    end
    
    local currDevices = self:getKanataDeviceList()

    -- Management operations can temporarily disconnect and reconnect virtual
    -- devices. Refresh the baseline without recursively launching the script.
    if self.activeManagementTask or os.time() < self.ignoreDeviceChangesUntil then
      prevDevices = currDevices
      self.logger.d("Device changes ignored while service state settles")
      return
    end

    local newDevices, removedDevices = self:getDeviceChanges(prevDevices, currDevices)

    -- Debug logging for device detection
    self.logger.d("Device check - Previous: " .. self:getDeviceListString(prevDevices) .. ", Current: " .. self:getDeviceListString(currDevices))
    self.logger.d("Device changes - Added: " .. #newDevices .. ", Removed: " .. #removedDevices)

    -- Log removed devices with include/exclude info
    if #removedDevices > 0 then
      self:logDeviceFilteringInfo(removedDevices, "removed")
      
      -- Track removed devices for reconnection detection
      for _, deviceName in ipairs(removedDevices) do
        self.recentlyRemovedDevices[deviceName] = true
      end
      
      -- Clean up old entries after 30 seconds
      hs.timer.doAfter(30, function()
        for deviceName, _ in pairs(self.recentlyRemovedDevices) do
          self.recentlyRemovedDevices[deviceName] = nil
        end
      end)
    end

    -- Log added devices with include/exclude info
    if #newDevices > 0 then
      self:logDeviceFilteringInfo(newDevices, "added")
      
      -- Check if any of these devices were recently removed (reconnection)
      for _, deviceName in ipairs(newDevices) do
        if self.recentlyRemovedDevices and self.recentlyRemovedDevices[deviceName] then
          self.logger.i("Device reconnected: " .. deviceName)
          self.recentlyRemovedDevices[deviceName] = nil
        end
      end
    end

    -- Restart if new devices detected
    if #newDevices > 0 then
      self:restartKanata(newDevices, true)
    end

    prevDevices = currDevices
  end)
  
  self.logger.i("Device monitoring timer started - checking every " .. self.checkInterval .. " seconds")
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
  -- If port is configured, use health check API
  if self.port then
    return self:checkKanataHealth()
  end
  
  -- Fallback to process-based detection
  return self:isKanataServiceRunningProcessBased()
end

function obj:isKanataServiceRunningProcessBased()
  -- Match the executable process name exactly. Searching the whole command
  -- line produces false positives from editors and extensions whose paths
  -- contain "kanata".
  local output, status = hs.execute("/usr/bin/pgrep -x kanata 2>/dev/null")
  return status == true and output ~= nil and output ~= ""
end

function obj:checkKanataHealth()
  if not self.port then
    return false
  end
  
  -- Send JSON request to get current layer name
  local jsonRequest = '{"RequestCurrentLayerName":{}}'
  local command = string.format('echo "%s" | nc -w1 127.0.0.1 %d', jsonRequest, self.port)
  
  local result = hs.execute(command)
  if not result or result == "" then
    return false
  end
  
  -- Check if response contains valid JSON with layer information
  -- Expected responses:
  -- {"LayerChange":{"new":"base"}}
  -- {"CurrentLayerName":{"name":"base"}}
  local hasLayerInfo = result:match('"name":') or result:match('"new":')
  
  if hasLayerInfo then
    self.logger.d("Kanata health check successful - port " .. self.port)
    return true
  else
    self.logger.d("Kanata health check failed - invalid response: " .. result)
    return false
  end
end

function obj:startKanataService(onComplete)
  if not self.restartScript then
    self.logger.e("Cannot start Kanata: restartScript not configured")
    return false
  end
  
  if not self:fileExists(self.restartScript) then
    self.logger.e("Cannot start Kanata: Restart script not found at " .. self.restartScript)
    return false
  end
  
  self.logger.i("Starting Kanata via management script: " .. self.restartScript)
  return self:runManagementScript(
    self.restartScript,
    "Kanata service started",
    { showAlert = false, onComplete = onComplete }
  )
end

function obj:handleAutoStart(onComplete)
  self.logger.i("Checking Kanata service status...")

  -- Validate requirements (kanataConfigPath is optional — only needed for device filtering)
  local missingRequirements = {}

  if not self.restartScript then
    table.insert(missingRequirements, "restartScript not configured and could not be auto-discovered")
  elseif not self:fileExists(self.restartScript) then
    table.insert(missingRequirements, "restartScript not found: " .. self.restartScript)
  end

  -- If requirements are missing, show alert and open console
  if #missingRequirements > 0 then
    local errorMsg = "Kanata service check failed; requirements missing:\n" .. table.concat(missingRequirements, "\n")
    self.logger.e(errorMsg)
    
    -- Show alert
    hs.alert.show("⚠️ Kanata Autostart Failed\nCheck Console for details", 5)
    
    -- Open Hammerspoon console
    hs.openConsole()
    
    if onComplete then onComplete(1) end
    return false
  end
  
  local isRunning = self:isKanataServiceRunning()
  if isRunning then
    self.logger.i("Kanata service is healthy; startup is not required")
    if onComplete then onComplete(0) end
    return true
  end
  
  self.logger.i("Kanata service is not running; starting it now...")
  local success = self:startKanataService(function(exitCode, stdOut, stdErr)
    if exitCode == 0 then
      self.logger.i("Kanata service started during Spoon startup")
      hs.alert.show("✅ Kanata started automatically", 2)
    else
      self.logger.e("Kanata startup failed")
      hs.alert.show("❌ Kanata startup failed\nCheck Console for details", 5)
      hs.openConsole()
    end
  
    if onComplete then onComplete(exitCode, stdOut, stdErr) end
  end)

  if not success then
    if onComplete then onComplete(1) end
    return false
  end

  return true
end

function obj:getKanataDeviceList()
  local kanataCmd = self:getKanataCommand()
  if not kanataCmd then
    return {}
  end
  
  -- Use --list flag (Kanata 1.10.0+), fallback to -l for older versions
  local output = hs.execute(kanataCmd .. " --list 2>/dev/null")
  local isNewFormat = false
  
  if not output or output == "" then
    -- Fallback to -l for older Kanata versions
    output = hs.execute(kanataCmd .. " -l 2>/dev/null")
  else
    -- Check if this is the new table format (Kanata 1.10.0+)
    if output:match("Available keyboard devices") or output:match("product_key") then
      isNewFormat = true
    end
  end
  
  if not output or output == "" then
    return {}
  end
  
  local devices = {}
  
  if isNewFormat then
    -- Parse new table format (Kanata 1.10.0+)
    -- Skip header lines and parse device names from table rows
    local inTable = false
    local headerSkipped = false
    
    for rawLine in output:gmatch("[^\r\n]+") do
      local line = rawLine:match("^%s*(.-)%s*$")  -- trim whitespace
      
      -- Skip empty lines and section headers
      if line == "" or line:match("^=+$") or line:match("Available keyboard devices") then
        goto continue
      end
      
      -- Skip the column header line
      if line:match("hash%s+vendor_id%s+product_id%s+product_key") then
        headerSkipped = true
        inTable = true
        goto continue
      end
      
      -- Skip the separator line (dashes)
      if line:match("^%-+$") then
        goto continue
      end
      
      -- If we're in the table section, parse device names
      if inTable and headerSkipped then
        -- Extract device name from the last column (product_key)
        -- Format: hash vendor_id product_id device_name
        -- Lines with device data start with 0x (hex hash)
        if line:match("^0x") then
          -- Split by whitespace and take everything after the third field
          -- Pattern: 0xHASH vendor_id product_id device_name...
          local parts = {}
          for part in line:gmatch("%S+") do
            table.insert(parts, part)
          end
          -- Device name is everything from the 4th field onwards
          if #parts >= 4 then
            local deviceName = table.concat(parts, " ", 4)
            if deviceName and deviceName ~= "" then
              devices[deviceName] = true
            end
          end
        end
      end
      
      ::continue::
    end
  else
    -- Parse old simple list format (pre-1.10.0)
    for rawLine in output:gmatch("[^\r\n]+") do
      local line = rawLine:match("^%s*(.-)%s*$")  -- trim whitespace
      if line ~= "" then
        devices[line] = true
      end
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
  
  for rawLine in content:gmatch("[^\r\n]+") do
    -- Trim whitespace
    local line = rawLine:match("^%s*(.-)%s*$")
    
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

function obj:getDeviceListString(devices)
  local deviceList = {}
  for name, _ in pairs(devices) do
    table.insert(deviceList, name)
  end
  return table.concat(deviceList, ", ")
end

function obj:logDeviceFilteringInfo(devices, action)
  -- Log which devices were included/excluded based on config
  if not self.kanataConfigPath or self.kanataConfigPath == "" then
    self.logger.d("No config file set - all devices will be monitored")
    return
  end
  
  local includedCount = 0
  local excludedCount = 0
  local includedDevices = {}
  local excludedDevices = {}
  
  for _, deviceName in ipairs(devices) do
    if self:shouldMonitorDevice(deviceName) then
      includedCount = includedCount + 1
      table.insert(includedDevices, deviceName)
    else
      excludedCount = excludedCount + 1
      table.insert(excludedDevices, deviceName)
    end
  end
  
  if includedCount > 0 then
    local includedList = table.concat(includedDevices, ", ")
    if self.useIncludeList then
      self.logger.i("Devices " .. action .. " (included by macos-dev-names-include): " .. includedList)
    else
      self.logger.i("Devices " .. action .. " (not excluded by macos-dev-names-exclude): " .. includedList)
    end
  end
  
  if excludedCount > 0 then
    local excludedList = table.concat(excludedDevices, ", ")
    if self.useIncludeList then
      self.logger.i("Devices " .. action .. " (excluded by macos-dev-names-include): " .. excludedList)
    else
      self.logger.i("Devices " .. action .. " (excluded by macos-dev-names-exclude): " .. excludedList)
    end
  end
  
  -- Log filtering mode for debugging
  if self.useIncludeList then
    self.logger.d("Using include mode - only devices in macos-dev-names-include are monitored")
  elseif #self.excludedDevices > 0 then
    self.logger.d("Using exclude mode - all devices except those in macos-dev-names-exclude are monitored")
  else
    self.logger.d("No filtering configured - all devices are monitored")
  end
end

function obj:restartKanata(newDevices, suppressLog)
  self.logger.i("restartKanata called with devices: " .. table.concat(newDevices, ", "))

  if self.activeManagementTask then
    self.logger.i("Management operation already running — restart skipped")
    return
  end

  -- Cooldown guard: kanata briefly disconnects during a restart, which makes the
  -- next device-check poll see "new" devices and fire another restart immediately.
  -- Block re-entry for restartCooldown seconds after the last restart.
  local now = os.time()
  if now - self.lastRestartTime < self.restartCooldown then
    local remaining = self.restartCooldown - (now - self.lastRestartTime)
    self.logger.i("Restart cooldown active (" .. remaining .. "s remaining) — skipping")
    return
  end
  self.lastRestartTime = now

  local deviceList = table.concat(newDevices, ", ")
  
  -- Check if Kanata service is already running
  local wasRunning = self:isKanataServiceRunning()
  if wasRunning then
    self.logger.i("Kanata service already running - restarting due to new device(s): " .. deviceList)
  else
    self.logger.i("New device(s) detected: " .. deviceList .. " - Starting Kanata")
  end
  
  if not self.restartScript then
    self.logger.w("No restart script configured or found")
    return
  end
  
  -- Run restart script with quiet flag to suppress "Service already running" messages
  local args = { "--force-restart" }
  if suppressLog then
    table.insert(args, "--quiet")
  end
  
  self:runManagementScript(self.restartScript, "Kanata restarted", {
    arguments = args,
    showAlert = not suppressLog,
    onComplete = function(exitCode)
      if exitCode ~= 0 then
        hs.timer.doAfter(2, function()
          if not self:isKanataServiceRunning() then
            hs.alert.show("⚠️ Kanata may need attention", 3)
          end
        end)
      end
    end
  })
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
          if not self.reloadOnConfigChange then
            self.logger.d("Kanata config file changed (reloadOnConfigChange disabled - no action taken)")
            self.configChangeTimer = nil
            return
          end

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
              self.logger.i("Config validation passed - restarting Kanata")
              hs.alert.show("Config valid — restarting Kanata")
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
  
  -- Show script progress in place of the normal status icon.
  local kanataRunning = self:isKanataServiceRunning()

  if self.operationProgress then
    self.menuBar:setTitle(tostring(self.operationProgress) .. "%")
    self.menuBar:setTooltip(self.operationStatus or "Kanata operation in progress")
  elseif self.isMonitoring and kanataRunning then
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

  table.insert(menu, { title = "-" })
  table.insert(menu, {
    title = "Install/Restart Kanata",
    fn = function()
      self:setServiceDesiredRunning(true)
      self:runManagementScript(
        self.restartScript or "kanata-install.sh",
        "Kanata install/restart complete"
      )
    end
  })
  table.insert(menu, {
    title = "Uninstall Kanata",
    fn = function()
      local choice = hs.dialog.blockAlert(
        "Uninstall Kanata?",
        "This stops and removes the Homebrew Kanata service. Your ~/.config/kanata files are preserved.",
        "Uninstall",
        "Cancel",
        "warning"
      )
      if choice == "Uninstall" then
        self:setServiceDesiredRunning(false)
        self:stopMonitoring(true)
        self:runManagementScript("kanata-uninstall.sh", "Kanata uninstalled")
      end
    end
  })
  
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
  
  -- Settings submenu
  table.insert(menu, { title = "-" })
  local settingsMenu = {
    { title = "Start Monitoring on Load: " .. (self.startMonitoringOnLoad and "✓" or "✗"),
      fn = function()
        self.startMonitoringOnLoad = not self.startMonitoringOnLoad
        self:updateMenuBar()
        hs.alert.show("startMonitoringOnLoad: " .. tostring(self.startMonitoringOnLoad))
      end
    },
    { title = "Reload on Config Change: " .. (self.reloadOnConfigChange and "✓" or "✗"),
      fn = function()
        self.reloadOnConfigChange = not self.reloadOnConfigChange
        self:updateMenuBar()
        hs.alert.show("reloadOnConfigChange: " .. tostring(self.reloadOnConfigChange))
      end
    },
    { title = "-" },
    { title = "Check kanata -l every: " .. self.checkInterval .. "s",
      fn = function()
        local btn, val = hs.dialog.textPrompt("Check Interval", "Seconds between device checks:", tostring(self.checkInterval), "OK", "Cancel")
        if btn == "OK" then
          local num = tonumber(val)
          if num and num > 0 then
            self.checkInterval = num
            hs.alert.show("Check interval set to " .. num .. "s")
            -- Restart monitoring to apply new interval
            if self.isMonitoring then
              self:stopMonitoring(true)
              self:startMonitoring(true)
            end
          end
        end
      end
    },
  }
  table.insert(menu, { title = "⚙️ Settings", menu = settingsMenu })
  
  -- Info section
  table.insert(menu, { title = "-" })
  table.insert(menu, {
    title = "Kanata.spoon v" .. self.version,
    fn = function() hs.urlevent.openURL(self.homepage) end
  })
  
  self.menuBar:setMenu(menu)
end

function obj:setOperationProgress(percent, status, generation)
  if generation and generation ~= self.operationGeneration then
    return
  end

  self.operationProgress = math.max(0, math.min(100, tonumber(percent) or 0))
  self.operationStatus = status
  self:updateMenuBar()
end

function obj:runManagementScript(scriptNameOrPath, successMessage, options)
  options = options or {}
  if self.activeManagementTask then
    self.logger.w("A Kanata management operation is already running")
    if options.showAlert ~= false then
      hs.alert.show("A Kanata operation is already in progress")
    end
    return false
  end

  local scriptPath = scriptNameOrPath
  if not scriptPath:match("^/") then
    scriptPath = self.spoonPath .. "/scripts/" .. scriptNameOrPath
  end
  local scriptName = scriptPath:match("([^/]+)$") or scriptPath

  if not self:fileExists(scriptPath) then
    self.logger.e("Management script not found: " .. scriptPath)
    hs.alert.show("Script not found:\n" .. scriptName)
    return false
  end

  self.operationGeneration = self.operationGeneration + 1
  local generation = self.operationGeneration
  local streamBuffer = ""
  local seenProgress = {}
  self.ignoreDeviceChangesUntil = os.time() + self.restartCooldown
  self:setOperationProgress(1, "Starting " .. scriptName, generation)
  self.logger.i(scriptName .. " progress 1%: Starting")

  local function consumeProgress(output, flush)
    if output and output ~= "" then
      streamBuffer = streamBuffer .. output
    end

    while true do
      local newline = streamBuffer:find("\n", 1, true)
      if not newline then
        break
      end
      local line = streamBuffer:sub(1, newline - 1)
      streamBuffer = streamBuffer:sub(newline + 1)
      local percent, status = line:match("^KANATA_PROGRESS=(%d+):(.*)$")
      if percent then
        local progressKey = percent .. ":" .. status
        if not seenProgress[progressKey] then
          seenProgress[progressKey] = true
          self.logger.i(scriptName .. " progress " .. percent .. "%: " .. status)
          self:setOperationProgress(percent, status, generation)
        end
      end
    end

    if flush and streamBuffer ~= "" then
      local percent, status = streamBuffer:match("^KANATA_PROGRESS=(%d+):(.*)$")
      if percent then
        local progressKey = percent .. ":" .. status
        if not seenProgress[progressKey] then
          seenProgress[progressKey] = true
          self.logger.i(scriptName .. " progress " .. percent .. "%: " .. status)
          self:setOperationProgress(percent, status, generation)
        end
      end
      streamBuffer = ""
    end
  end

  local task = hs.task.new(scriptPath, function(exitCode, stdOut, stdErr)
    consumeProgress(stdOut, true)
    self.activeManagementTask = nil
    self.kanataBinaryPath = nil
    self.ignoreDeviceChangesUntil = os.time() + math.max(self.restartCooldown, self.checkInterval * 2)

    if exitCode == 0 then
      self.logger.i(scriptName .. " completed successfully")
      self:setOperationProgress(100, successMessage, generation)
      if options.showAlert ~= false then
        hs.alert.show("✅ " .. successMessage)
      end
    else
      self.logger.e(scriptName .. " failed with exit code " .. tostring(exitCode))
      if stdOut and stdOut ~= "" then
        self.logger.e("Script output: " .. stdOut)
      end
      if stdErr and stdErr ~= "" then
        self.logger.e("Script error: " .. stdErr)
      end
      self.operationStatus = scriptName .. " failed"
      self:updateMenuBar()
      if options.showAlert ~= false then
        hs.alert.show("❌ " .. scriptName .. " failed\nCheck Hammerspoon Console")
      end
    end

    if options.onComplete then
      options.onComplete(exitCode, stdOut, stdErr)
    end

    hs.timer.doAfter(0.75, function()
      if self.operationGeneration == generation and not self.activeManagementTask then
        self.operationProgress = nil
        self.operationStatus = nil
        self:updateMenuBar()
      end
    end)
  end, function(streamTask, stdOut, stdErr)
    -- Hammerspoon may invoke the stream callback once more after completion.
    -- Ignore that final nil-task call so stale output cannot restore progress.
    if streamTask then
      consumeProgress(stdOut, false)
    end
    if stdErr and stdErr ~= "" then
      self.logger.d(scriptName .. " stderr: " .. stdErr)
    end
    return true
  end, options.arguments or {})

  if not task or not task:start() then
    self.logger.e("Failed to execute management script: " .. scriptPath)
    self.operationProgress = nil
    self.operationStatus = nil
    self:updateMenuBar()
    hs.alert.show("❌ Failed to start " .. scriptName)
    return false
  end

  self.activeManagementTask = task
  return true
end

function obj:startService()
  self.logger.i("Starting Kanata service and monitoring")
  self:setServiceDesiredRunning(true)
  
  -- Start Kanata if not running
  if not self:isKanataServiceRunning() then
    local success = self:startKanataService(function(exitCode)
      if exitCode == 0 then
        if not self.isMonitoring then
          self:startMonitoring(true)
        end
        hs.alert.show("✅ Service started")
      end
    end)
    if not success then
      hs.alert.show("Failed to start Kanata service")
    end
    return
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
  self:setServiceDesiredRunning(false)

  if self.isMonitoring then
    self:stopMonitoring(true)
  end

  self:runManagementScript(
    self.restartScript or "kanata-install.sh",
    "Kanata service stopped",
    { arguments = { "--stop" } }
  )
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

  if self.isMonitoring then
    self:stopMonitoring(true)
  end

  if self:isKanataServiceRunning() then
    local started = self:runManagementScript(
      self.restartScript or "kanata-install.sh",
      "Kanata service stopped",
      {
        arguments = { "--stop" },
        showAlert = false,
        onComplete = function()
          self.logger.i("Quitting Hammerspoon...")
          hs.osascript.applescript('tell application "Hammerspoon" to quit')
        end
      }
    )
    if started then
      return
    end
  end

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

