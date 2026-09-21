# Kanata.spoon

Hammerspoon Spoon for monitoring and managing [Kanata](https://github.com/jtroo/kanata) keyboard remapper on macOS.

Kanata.spoon 1.11.2 targets Kanata 1.12.0.

## Features

- 🔄 Automatic device detection and Kanata restart
- 🎛️ Menu bar controls
- 📊 Numeric menu-bar progress for install, restart, stop, and uninstall
- ⚙️ Config validation on changes
- 🛌 Sleep/wake handling
- 🔗 URL scheme support

<img width="926" height="904" alt="CleanShot 2026-02-10 at 21 55 24@2x" src="https://github.com/user-attachments/assets/0596881a-dd0d-4656-bce1-e0d683df4bf7" />

## Prerequisites (one-time setup)

Install and start Kanata via Homebrew:

```bash
bash ~/.hammerspoon/Spoons/Kanata.spoon/scripts/kanata-install.sh
```

The installer and restart action use the existing `supa` login-keychain item
for non-interactive administrator access. If that item is unavailable, they
fall back to the normal `sudo` prompt in Terminal or the standard macOS
administrator dialog when launched from Hammerspoon.

The Spoon bundles the standalone Karabiner VirtualHID DriverKit 6.2.0 package,
verifies its official SHA-256 digest, and installs/activates it with the same
package and LaunchDaemon workflow used by KeyPath. The full Karabiner-Elements
application is not required.

> Grant permissions in **System Settings → Privacy & Security**:
> - **Input Monitoring** — allows kanata to read keyboard events
> - **Accessibility** — **required for mouse commands** (movemouse-*, scroll, etc.)
>
> Both are needed. See [Mouse commands silently fail](#mouse-commands-silently-fail-when-running-as-a-service) below.

## Quick Start

1. Copy `Kanata.spoon` to `~/.hammerspoon/Spoons/`
2. Add to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("Kanata")
spoon.Kanata.startMonitoringOnLoad = true  -- restart kanata when new keyboards are detected
spoon.Kanata:start()
```

3. Reload Hammerspoon

That's it. The spoon auto-discovers the idempotent `kanata-install.sh` management script and auto-detects your config at `~/.config/kanata/kanata.kbd`.

## Configuration

```lua
hs.loadSpoon("Kanata")

-- Logging ('debug', 'info', 'warn', 'error', 'nothing')
spoon.Kanata.logger.setLogLevel('info')

-- Path to Kanata config (auto-detected at ~/.config/kanata/kanata.kbd)
-- Only set this if your config is in a non-standard location.
-- When set, parses macos-dev-names-include/exclude for device filtering and validates
-- config with `kanata --check` before reloading.
spoon.Kanata.kanataConfigPath = os.getenv("HOME") .. "/.config/kanata/kanata.kbd"

-- Shared install/restart script (auto-discovered from spoon's scripts/ folder)
-- Override only if you keep the script somewhere else.
-- spoon.Kanata.restartScript = hs.configdir .. "/Spoons/Kanata.spoon/scripts/kanata-install.sh"

-- How often to poll for device changes (seconds, default: 5)
spoon.Kanata.checkInterval = 5

-- Health check port (optional — more reliable than process-based detection)
-- Requires kanata to be started with: --port 10000
-- spoon.Kanata.port = 10000

spoon.Kanata.showMenuBar = true           -- ⌨️ icon in menu bar
spoon.Kanata.startMonitoringOnLoad = true -- watch for new keyboards, auto-restart kanata

-- Auto-reload kanata when kanata.kbd is saved (off by default)
-- Requires monitoring to be active and kanataConfigPath to be set
-- spoon.Kanata.reloadOnConfigChange = true

spoon.Kanata:start()
```

See `config.example.lua` for a fully-annotated example.

## Autostart

Brew services registers a system LaunchDaemon so kanata starts at boot automatically. Whenever the Spoon starts, it uses an exact `kanata` process health check and starts the service through the shared management script when necessary. An explicit **Stop Service** choice is persisted across Spoon and Hammerspoon restarts; **Start Service** changes the saved state back to running. Device monitoring remains optional:

```lua
spoon.Kanata.startMonitoringOnLoad = true
spoon.Kanata:start()
```

Stopping the service or quitting Hammerspoon first stops Kanata and then
restarts the KeepAlive VirtualHID daemon. This clears stale virtual keyboard
state so physical keyboards immediately return to normal macOS passthrough.

## Menu Bar

Click ⌨️ for:

- **Start/Stop Service** — controls both Kanata service and device monitoring
- **Install/Restart and Uninstall Kanata** — runs the bundled management scripts directly
- **Open Kanata Config** / **Open Hammerspoon Config**
- **Show Console** / **Quit Hammerspoon**
- **⚙️ Settings** — toggle monitoring options inline

## URL Scheme

```bash
open "hammerspoon://kanata?action=start"   # start monitoring
open "hammerspoon://kanata?action=stop"    # stop monitoring
open "hammerspoon://kanata?action=toggle"  # toggle monitoring
```

## How It Works

| Feature | Mechanism |
|---------|-----------|
| Device monitoring | `kanata --list` polled every `checkInterval` seconds |
| Service detection | Process scan, or JSON health-check API when `port` is set |
| Device filtering | Parses `macos-dev-names-include`/`macos-dev-names-exclude` from config |
| Config validation | `kanata --check` before reloading on file change |
| Install / restart | Calls the idempotent `kanata-install.sh`; healthy dependencies and services are preserved |
| Start / stop service | Calls `kanata-install.sh` in its normal or `--stop` mode and controls monitoring |

## Configuration Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `checkInterval` | number | 5 | Seconds between device checks |
| `kanataConfigPath` | string | auto | Path to Kanata config (for device filtering) |
| `restartScript` | string | auto | Path to the shared `kanata-install.sh` management script |
| `port` | number | nil | Enable JSON health-check API on this port |
| `showMenuBar` | boolean | true | Show menu bar icon |
| `startMonitoringOnLoad` | boolean | false | Auto-start device monitoring |
| `reloadOnConfigChange` | boolean | false | Validate and restart kanata when `kanata.kbd` is saved |
| `restartCooldown` | number | 15 | Seconds to block auto-restarts after one fires (prevents restart loops) |

## Known Gotchas

### Mouse commands stop working after restart

The Homebrew formula plist ships with `--no-wait` (skips the interactive "press Enter to exit" prompt) but **not** `--nodelay` (removes the 2-second startup sleep). Without `--nodelay`, kanata's virtual mouse device does not finish initializing and mouse layer actions silently fail for the lifetime of that process.

The shared install/restart script automatically patches the formula plist to add `--nodelay` before starting the service, so this is handled for you. If you ever start kanata manually, always include `--nodelay`:

```bash
sudo kanata -c ~/.config/kanata/kanata.kbd --nodelay
```

### Two kanata instances running = broken keyboard / mouse

Running two kanata processes simultaneously (one from a legacy LaunchDaemon and one from brew services, or one from a terminal) will cause unpredictable behavior — keys drop, mouse movement stops, or the keyboard locks up entirely.

Check for duplicate instances:

```bash
ps aux | grep -E "^root.*kanata" | grep -v grep
```

If you see more than one, kill them all and start fresh:

```bash
sudo pkill -x kanata
sudo brew services start kanata
```

The old scripts used `/Library/LaunchDaemons/com.example.kanata.plist`. If that file still exists, remove it:

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.example.kanata.plist
sudo rm /Library/LaunchDaemons/com.example.kanata.plist
```

### Mouse commands silently fail when running as a service

`movemouse-*`, scroll, and other pointer actions work fine when you run kanata manually in a terminal (`sudo kanata ... --debug`) but silently do nothing when kanata is started via `brew services` or the spoon.

**Root cause**: when kanata runs as a system `LaunchDaemon` it has no user-session context. macOS checks the binary's own TCC entry for permission to inject pointer events — and that entry doesn't exist until you explicitly grant it.

**Fix**: add the kanata binary to **System Settings → Privacy & Security → Accessibility**.

The binary path is `/opt/homebrew/opt/kanata/bin/kanata`. Because it's a CLI binary, the macOS file picker hides it by default — use the keyboard shortcut to navigate there:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click **+**
3. Press **⌘⇧G** (Go to Folder)
4. Paste: `/opt/homebrew/opt/kanata/bin`
5. Press **Return**, select `kanata`, click **Open**

Repeat the same steps for **Input Monitoring** while you're there.

> Why does it work in the terminal? When you run `sudo kanata` from Terminal, the process runs in your Aqua login session and macOS allows it to inherit the session's TCC context (including Terminal.app's existing Accessibility permission). That inheritance disappears when kanata runs as a headless LaunchDaemon.

### Privilege level

Both start paths run kanata as **root**:

| Method | How it runs |
|--------|-------------|
| `sudo brew services start kanata` | System LaunchDaemon, user = root |
| Kanata.spoon autostart | Calls `kanata-install.sh`; uses the `supa` keychain item, with macOS authorization as fallback |

## Troubleshooting

**Monitoring doesn't start**
- `which kanata` — verify it's installed
- Check Hammerspoon Console for errors

**Autostart fails**
- Check Console for the missing-requirement message
- Run `bash ~/.hammerspoon/Spoons/Kanata.spoon/scripts/kanata-install.sh` in Terminal to test

**Config changes not detected**
- Verify `kanataConfigPath` points to the right file

## Requirements

- macOS 12 (Ventura)+ recommended
- [Hammerspoon](https://www.hammerspoon.org/) 0.9.90+
- [Kanata 1.12.0](https://github.com/jtroo/kanata/releases/tag/v1.12.0) installed via `brew install kanata`
- [Karabiner VirtualHID DriverKit 6.2.0](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v6.2.0) (bundled and installed automatically)
- [Permissions](https://github.com/jtroo/kanata/issues/1264#issuecomment-2763085239) granted in System Settings

## License

MIT - See [LICENSE](LICENSE) file

## Links

- [Hammerspoon](https://www.hammerspoon.org/)
- [Kanata](https://github.com/jtroo/kanata)
- [Karabiner DriverKit VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)
