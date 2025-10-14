# Kanata.spoon

Hammerspoon Spoon for monitoring and managing [Kanata](https://github.com/jtroo/kanata) keyboard remapper on macOS.

## Features

- 🔄 Automatic device detection and Kanata restart
- 🎛️ Menu bar controls
- 🚀 Optional Raycast integration
- ⚙️ Config validation on changes
- 🛌 Sleep/wake handling
- 🔗 URL scheme support

<img width="228" height="388" alt="CleanShot 2025-10-13 at 20 45 08" src="https://github.com/user-attachments/assets/460d7f8f-98e0-4bc3-8b8c-b24324f54fa0" />

## Quick Start

### Installation

1. Copy `Kanata.spoon` to `~/.hammerspoon/Spoons/`
2. Add to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("Kanata")
spoon.Kanata.kanataConfigPath = os.getenv("HOME") .. "/.config/kanata/kanata.kbd"
spoon.Kanata.restartScript = "Spoons/Kanata.spoon/scripts/kanata-restart.sh"
spoon.Kanata:start()
```

3. Reload Hammerspoon

## Configuration

```lua
hs.loadSpoon("Kanata")

-- Required for autostart
spoon.Kanata.restartScript = "Spoons/Kanata.spoon/scripts/kanata-restart.sh"

-- Optional
spoon.Kanata.kanataConfigPath = os.getenv("HOME") .. "/.config/kanata/kanata.kbd"
spoon.Kanata.checkInterval = 5  -- Check for new devices every 5 seconds
spoon.Kanata.showMenuBar = true
spoon.Kanata.startMonitoringOnLoad = false
spoon.Kanata.autoStartKanata = false
spoon.Kanata.useRaycast = false  -- Enable Raycast integration

spoon.Kanata:start()
```

### Raycast Integration

To add Raycast commands to the menu:

1. Install [Raycast](https://www.raycast.com/)
2. Add `~/.config/hammerspoon/Spoons/Kanata.spoon/scripts/` to Raycast Script Commands
3. Enable in config:
   ```lua
   spoon.Kanata.useRaycast = true
   ```
4. Reload Hammerspoon
5. Approve scripts on first use (macOS will prompt)

**Note**: When enabled, automatically calls `hs.allowAppleScript(true)`.

See [RAYCAST.md](RAYCAST.md) for detailed setup.

## Menu Bar

Click the ⌨️ icon for:

- **Start/Stop Service** - Controls both Kanata service and monitoring
- **Start/Stop Monitor** - Controls monitoring only
- **Restart Kanata** (Raycast) - Opens Raycast command
- **Stop Kanata** (Raycast) - Opens Raycast command
- **Cleanup Kanata** (Raycast) - Opens Raycast command
- **Install Kanata** (Raycast) - Opens Raycast command
- **Open Kanata Config** - Opens your config file
- **Open Hammerspoon Config** - Opens init.lua
- **Hammerspoon Preferences** - Opens preferences
- **Show Console** - Opens Hammerspoon console
- **Quit Hammerspoon** - Stops services and quits

## URL Scheme

Control via URLs:

```bash
open "hammerspoon://kanata?action=start"   # Start monitoring
open "hammerspoon://kanata?action=stop"    # Stop monitoring
open "hammerspoon://kanata?action=toggle"  # Toggle monitoring
```

## Autostart

To automatically start Kanata at boot:

```lua
spoon.Kanata.kanataConfigPath = os.getenv("HOME") .. "/.config/kanata/kanata.kbd"
spoon.Kanata.restartScript = "Spoons/Kanata.spoon/scripts/kanata-restart.sh"
spoon.Kanata.autoStartKanata = true
spoon.Kanata.startMonitoringOnLoad = true
```

If requirements are missing, you'll see an alert with details.

## How It Works

- **Device Monitoring**: Checks `kanata -l` every 5 seconds for new devices
- **Service Detection**: Checks port 10000 (Kanata's TCP server)
- **Device Filtering**: Respects `macos-dev-names-include` and `macos-dev-names-exclude` from config
- **Config Validation**: Uses `kanata --check` before reloading

## Configuration Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `checkInterval` | number | 5 | Seconds between device checks |
| `kanataConfigPath` | string | nil | Path to Kanata config |
| `restartScript` | string | nil | Path to restart script (required for autostart) |
| `showMenuBar` | boolean | true | Show menu bar icon |
| `startMonitoringOnLoad` | boolean | false | Auto-start monitoring |
| `autoStartKanata` | boolean | false | Auto-start Kanata at boot |
| `useRaycast` | boolean | false | Add Raycast commands to menu |

## Methods

### `start()`
Initializes the spoon.

### `stop()`
Stops monitoring and cleans up.

### `startMonitoring([suppressLog])`
Starts device monitoring.

### `stopMonitoring([suppressAlert])`
Stops device monitoring.

### `startService()`
Starts both Kanata service and monitoring.

### `stopService()`
Stops both Kanata service and monitoring.

## Troubleshooting

### Monitoring doesn't start
- Check if Kanata is installed: `which kanata`
- Check Hammerspoon Console for errors

### Raycast scripts don't work
- Verify scripts folder added to Raycast
- Approve scripts on first use (macOS will prompt)
- Check scripts are executable: `chmod +x scripts/*.sh`

### Config changes not detected
- Verify `kanataConfigPath` is correct
- Check file exists: `ls -la ~/.config/kanata/kanata.kbd`

### Autostart fails
- Check console for missing requirements
- Verify `restartScript` path is correct
- Test script manually: `bash /path/to/kanata-restart.sh`

## Requirements

- macOS 10.12+
- [Hammerspoon](https://www.hammerspoon.org/) 0.9.90+
- [Kanata](https://github.com/jtroo/kanata)
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) (required by Kanata)

## License

MIT - See [LICENSE](LICENSE) file

## Links

- [Hammerspoon](https://www.hammerspoon.org/)
- [Kanata](https://github.com/jtroo/kanata)
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/)
