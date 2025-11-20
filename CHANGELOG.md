# Changelog

All notable changes to Kanata.spoon will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.3] - 2025-10-17

### Fixed
- **Kanata 1.10.0 Compatibility**: Updated for Kanata 1.10.0 compatibility
  - Changed device listing from `-l` to `--list` flag (with fallback for older versions)
  - **Fixed device list parsing** for new table format in Kanata 1.10.0
    - New format includes headers and table structure
    - Properly extracts device names from `product_key` column
    - Handles device names with spaces correctly
    - Maintains backward compatibility with old simple list format
  - Improved process detection to handle different command formats
  - Enhanced error handling in restart script with better exit code reporting
  - Added support for "Service is disabled" error handling
  - Improved script error logging with stdout and stderr capture
  - **Fixed Virtual HID server socket access**: Reverted to LaunchDaemon
    - Kanata 1.10.0 requires root access to `/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server`
    - LaunchAgent (user-level) cannot access root-only directories
    - LaunchDaemon (system-level) runs as root and has required access
    - Fixes "Permission denied" errors when accessing Virtual HID server socket

### Changed
- **Service Type**: Reverted to LaunchDaemon (system-level) - required for Virtual HID access
  - **Critical Fix**: Kanata 1.10.0 requires root access to Virtual HID server socket
  - Socket location: `/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server`
  - LaunchDaemon runs as root and can access the root-only socket directory
  - Service runs from `/Library/LaunchDaemons/` (system-level)
  - Logs stored in `/Library/Logs/Kanata/` (system-level)
  - **Note**: This is required for Kanata 1.10.0+ with DriverKit v6
  - Scripts handle migration from LaunchAgent back to LaunchDaemon

### Changed
- **Restart Script**: Enhanced error handling and reporting
  - Better exit code reporting with detailed error messages
  - Handles "Service is disabled" case by enabling the service
  - Improved logging for troubleshooting restart failures
  - Added wait time between stop and start operations

### Note
- **Karabiner DriverKit v6**: Kanata 1.10.0 requires Karabiner DriverKit v6
  - Make sure you have the latest Karabiner Elements installed
  - The spoon will work with Kanata 1.10.0+ and maintains backward compatibility

## [1.0.2] - 2025-10-14

### Added
- **Health Check API**: New port-based health checking system
  - Added `port` variable for configuring Kanata API port (e.g., `kanata -p 10000`)
  - Uses JSON API to verify Kanata is running and healthy, not just the process
  - Sends `{"RequestCurrentLayerName":{}}` and validates response
  - Falls back to process-based detection when port not configured
  - More reliable than checking process list alone

### Changed
- **Menu Bar**: Simplified menu options
  - Removed "Monitoring Inputs..." and "Start Monitoring" options to reduce redundancy
  - "Start/Stop Service" controls both Kanata service and monitoring
- **Health Detection**: Improved Kanata service detection logic
  - When port is configured, uses API health check instead of process detection
  - Better reliability for determining if Kanata is actually responding
- **Logging**: Enhanced device detection logging
  - Added detailed logging for device additions and removals
  - Shows which devices are included/excluded by config sections
  - Logs when service is restarted while already running
- **Menu Bar Animation**: Added restart animation
  - Shows 🔄/⏳/⚡ animation when Kanata is restarting
  - Visual feedback for device detection and service restarts
  - Fixed tooltip method error in animation function
- **Device Reconnection Detection**: Enhanced device tracking
  - Added specific "Device reconnected" logging for devices that were recently removed
  - Tracks recently removed devices for 30 seconds to detect reconnections
  - Added debug logging to help troubleshoot device detection issues
- **Logging Cleanup**: Simplified log messages
  - Removed redundant "*** DEVICE(S) REMOVED/ADDED ***" messages
  - Removed "Showing restart animation" message
  - Rely on detailed filtering info messages instead
- **Auto-start Fix**: Fixed port-based health check conflict
  - Auto-start now uses process-based detection instead of health check API
  - Prevents chicken-and-egg problem when port is configured
  - Service will start automatically even when port-based health check is enabled

## [1.0.1] - 2025-10-14

### Fixed
- **Kanata Detection**: Fixed issue where Kanata binary couldn't be found at startup
  - Now checks common installation paths (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.cargo/bin`, etc.)
  - No longer relies solely on PATH environment variable
  - Caches binary path for better performance
  - GUI applications on macOS don't always inherit terminal PATH, this fix resolves that

### Changed
- **Menu Bar Icons**: 
  - 🔎 icon now shows when monitoring is active but Kanata service is not running
  - ⌨️ icon shows when both monitoring and Kanata service are running
  - 😵️ icon shows when monitoring is inactive
- **Menu Controls**: 
  - Renamed "Monitoring..." to "Monitoring Inputs..." for clarity
  - "Monitoring Inputs..." button now only stops monitoring (not the Kanata service)
  - Improved menu item descriptions and tooltips

## [1.0.0] - 2025-10-13

### Features
- Automatic device monitoring and Kanata restart
- Menu bar controls
- Raycast integration (optional)
- Config validation on changes
- Sleep/wake handling
- Auto-start at boot
- URL scheme support

### Menu Controls
- **Start/Stop Service** - Controls both Kanata and monitoring
- **Start/Stop Monitor** - Controls monitoring only
- Raycast commands (when enabled)
- Config file access
- Hammerspoon preferences and console

### Added
- Initial release of Kanata.spoon
- Device monitoring and automatic Kanata restart on new device detection
- Menu bar controls with toggleable monitoring
- Optional Raycast integration via deeplinks
- Config file validation on changes
- Device filtering support (respects `macos-dev-names-include` and `macos-dev-names-exclude`)
- Sleep/wake handling (auto-stop on sleep, auto-resume on wake)
- URL scheme support (`hammerspoon://kanata?action=start/stop/toggle`)
- Auto-start Kanata service at boot with requirement validation
- Show Console menu option
- Quit Hammerspoon menu option
- Configurable check intervals
- Optional menu bar display
- Comprehensive logging with hs.logger
- Example configuration file
- Complete documentation (README, RAYCAST guide, AUTOSTART guide, QUICKSTART)
- MIT License

### Features
- **Device Monitoring**: Automatically detects new input devices and restarts Kanata
- **Menu Bar Integration**: Quick access to controls via menu bar icon
- **Raycast Integration**: Optional Raycast script commands in menu
- **Config Validation**: Validates Kanata config changes before reloading
- **Device Filtering**: Respects device include/exclude lists from Kanata config
- **Sleep/Wake Handling**: Intelligently manages monitoring during sleep/wake cycles
- **URL Scheme**: Control via `hammerspoon://kanata?action=start/stop/toggle`
- **Auto-Start**: Optional automatic Kanata service start at boot
- **Highly Configurable**: All paths, intervals, and behaviors can be customized

### Scripts Included
- `kanata-install.sh`: Install and configure Kanata
- `kanata-restart.sh`: Restart Kanata service
- `kanata-stop.sh`: Stop Kanata service
- `kanata-cleanup.sh`: Clean up and uninstall Kanata

### Documentation
- README.md: Complete documentation with features, installation, and API reference
- RAYCAST.md: Raycast integration setup guide
- AUTOSTART.md: Autostart configuration guide
- QUICKSTART.md: 5-minute quick start guide
- config.example.lua: Comprehensive example configuration
- Inline code documentation

### Technical Details
- Spoon follows Hammerspoon Spoon conventions
- Uses `hs.timer` for periodic device checks
- Uses `hs.pathwatcher` for config file monitoring
- Uses `hs.caffeinate.watcher` for sleep/wake events
- Uses `hs.urlevent` for URL scheme handling
- Uses `hs.menubar` for menu bar integration
- Uses `hs.task` for running external scripts

---

[1.0.0]: https://github.com/plasmadice/Kanata.spoon/releases/tag/v1.0.0
