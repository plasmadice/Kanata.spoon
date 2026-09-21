# Changelog

All notable changes to Kanata.spoon will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.11.2] - 2026-09-21

### Changed
- **Kanata 1.12 target**: the installer now upgrades older Homebrew installations to Kanata 1.12.0 and verifies that Homebrew supplied the targeted version.
- **Permission migration guidance**: the installer now tells users to remove stale versioned Cellar entries and add `/opt/homebrew/opt/kanata/bin/kanata` to both Input Monitoring and Accessibility.
- **Complete uninstall**: the uninstaller now handles root-owned Homebrew kegs, the current `sh.brew.kanata` service, service logs, and stale kanata-tray configuration.
- **No Raycast dependency**: removed Raycast integration and script metadata. Privileged operations again use the existing `supa` login-keychain password automatically, with normal `sudo` or macOS authorization as fallbacks.
- **Bundled standalone DriverKit**: install and restart now verify, install, activate, and keep alive the official Karabiner VirtualHID DriverKit 6.2.0 package using KeyPath's package-and-LaunchDaemon workflow. The full Karabiner-Elements app is no longer required.
- **Homebrew bottle config path**: install and restart scripts now replace any bottle-builder `--cfg` path with the current user's `~/.config/kanata/kanata.kbd`.
- **Direct management actions**: added combined Install/Restart and Uninstall actions in the Hammerspoon menu without routing through Raycast. Service stopping remains part of the combined Start/Stop Service control.
- **Unified service workflow**: install, restart, start, stop, autostart, and automatic device restarts use the idempotent `kanata-install.sh`; healthy dependencies and services are preserved.
- **Numeric operation progress**: management scripts emit checkpoint percentages, shown directly in the menu-bar item and written to the Hammerspoon Console until each operation completes.
- **Stable progress sequence**: duplicate final `hs.task` output is de-duplicated, so progress advances once from 1% through 100% instead of replaying.
- **Restart-loop prevention**: device monitoring refreshes its baseline while service changes settle, preventing virtual-device reconnects from launching another management cycle.
- **Startup health enforcement**: starting the Spoon always checks Kanata service health and starts it when necessary; monitoring starts only after that check succeeds.
- **Persisted service intent**: explicit Start/Stop Service choices survive Spoon and Hammerspoon restarts. Unexpected service exits are restarted only when the saved desired state is running.
- **Exact process detection**: replaced command-line substring matching with `pgrep -x kanata`, avoiding false positives from editor extensions and paths containing “kanata.”
- **Safe keyboard release**: Stop Service and Hammerspoon shutdown now stop Kanata and restart the KeepAlive VirtualHID daemon, following KeyPath's recovery method to clear stale reports and restore normal physical-keyboard passthrough.

### Compatibility
- Validated the existing `~/.config/kanata/kanata.kbd` with the official Kanata 1.12.0 arm64 binaries.
- Reviewed the Kanata 1.12 behavior changes. The config uses `switch`, but not the affected `rpt-any` or chordsv2 paths, so no config migration is required.
- The 1.12.1 prerelease fixes left/right inertial mouse-wheel state, which is compatible with the config's `mwheel-left` and `mwheel-right` actions.

## [1.2.0] - 2026-04-29

### Added
- **`reloadOnConfigChange` option** (default: `false`): auto-validate and restart kanata when `kanata.kbd` is saved. Previously this was always on; it is now opt-in. Toggle in ⚙️ Settings menu or set `spoon.Kanata.reloadOnConfigChange = true` in `init.lua`.
- **`restartCooldown` option** (default: 15 s): blocks additional auto-restarts within N seconds of the last one. Prevents a restart loop caused by kanata briefly disconnecting during a `brew services restart`, which made the next device-check poll see "new" devices and fire another restart.
- **`kanata-legacy-cleanup.sh`**: one-time migration script that removes artifacts from the old custom-LaunchDaemon installation (plist files, log directory, non-Homebrew binaries). Requires interactive confirmation; never touches `~/.config/kanata/` or the current Homebrew install.

### Fixed
- **Restart animation stuck in loop**: calling `showRestartAnimation` while one was already running leaked the `doEvery` timer (overwritten without being stopped) and left the anonymous `doAfter` cleanup timer uncancellable. Both timers are now tracked and explicitly stopped before a new animation starts.
- **Mouse commands silently fail when running as a service**: documented that `Accessibility` permission (System Settings → Privacy & Security → Accessibility) must be granted to `/opt/homebrew/opt/kanata/bin/kanata`. Without it, `movemouse-*` and scroll actions work in a terminal `sudo` session (which inherits Terminal.app's TCC grants) but silently do nothing when kanata runs as a headless LaunchDaemon.

## [1.1.0] - 2026-04-21

### Changed
- **Homebrew service workflow**: Kanata is now managed via `sudo brew services start kanata` instead of a custom LaunchDaemon. All four scripts (`kanata-install.sh`, `kanata-restart.sh`, `kanata-stop.sh`, `kanata-uninstall.sh`) are rewritten to use `brew services` accordingly.
- **`init()` auto-discovery**: `restartScript` is now auto-discovered from the spoon's `scripts/` folder — no need to set it in `init.lua`. `spoonPath` is resolved via `hs.configdir` for reliable script lookup in all contexts.
- **`autoStartKanata` simplified**: `kanataConfigPath` is no longer a hard requirement for autostart. It is only needed for device filtering (`macos-dev-names-include`/`macos-dev-names-exclude`) and config validation. Autostart now only requires the kanata binary and restart script.
- **`stopService()` and `quitHammerspoon()`**: Always use `kanata-stop.sh` directly; Raycast is no longer required for basic stop/quit.
- **Removed `checkForUpdates`**: Not applicable to brew-managed binaries.
- **Brew resolution in scripts**: All scripts resolve `brew` in priority order (`/opt/homebrew/bin/brew` → `/usr/local/bin/brew` → `$PATH`) so both Apple Silicon and Intel Homebrew setups work correctly, including in Raycast's restricted `PATH` environment.

### Fixed
- **Mouse commands silently fail when run as a service**: `movemouse-*` and other pointer actions work when starting kanata manually (`sudo kanata --debug`) but do nothing when run via `brew services` or the spoon. Root cause: as a headless system `LaunchDaemon`, kanata has no login-session context and macOS requires the binary itself to have **Accessibility** permission in TCC (System Settings → Privacy & Security → Accessibility). Adding `/opt/homebrew/opt/kanata/bin/kanata` to Accessibility resolves the issue. **Input Monitoring** should be granted there too. Note: the terminal `sudo` case works because the process inherits Terminal.app's existing session-level TCC grants.

### Migration from 1.0.x
If you had the old LaunchDaemon setup (`/Library/LaunchDaemons/com.example.kanata.plist`), run `scripts/kanata-uninstall.sh` to remove legacy plists and log directories. Then follow the new Quick Start in README.md.

**Context (1.0.3 era)**: Kanata 1.10.x needed root access to the Karabiner Virtual HID server socket under `/Library/Application Support/org.pqrs/tmp/rootonly/`, which required a system LaunchDaemon. Upstream Homebrew now handles this transparently via `sudo brew services`.

## [Unreleased]

### Notes

- **Homebrew service workflow**: Kanata can be run with Homebrew’s service support instead of this spoon’s LaunchDaemon + scripts. Typical flow:
  1. `brew install karabiner-elements`
  2. `brew install kanata`
  3. `sudo brew services start kanata`
  Keep Karabiner-Elements.app **out** of Login Items and quit its menu bar app if you only need the virtual HID driver. System Settings → Privacy & Security permissions for Kanata are still required.
- **What we used to work around (1.0.3 era)**: Kanata 1.10.x needed root access to the Karabiner Virtual HID server socket under `/Library/Application Support/org.pqrs/tmp/rootonly/`, so the install scripts used a **system LaunchDaemon** (`/Library/LaunchDaemons/com.example.kanata.plist`), logs under `/Library/Logs/Kanata/`, and the spoon could auto-start the service via `kanata-restart.sh`. If you are **migrating away** from that stack: unload/remove the LaunchDaemon (see `scripts/kanata-uninstall.sh`), remove `hs.loadSpoon("Kanata")` / `spoon.Kanata:start()` from `~/.hammerspoon/init.lua`, then use `brew services` as above. If you **stay** on the spoon, nothing in this note changes spoon behavior.

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
